{-# LANGUAGE ExistentialQuantification #-}

module FFIWrappers
  ( call
  , callIO
  , callCBOR
  , callCBORIO
  , offer
  , offerCBOR
  , tenkeiFree
  , toPointer
  , toFunPointer
  , toPointerF
  , fromPointer
  , fromFunPointer
  ) where

import Foreign
import Foreign.C
import System.IO.Unsafe

import Data.Binary.CBOR
import Data.CBOR

import Data.Binary.Get
import Data.Binary.Put

import Data.ByteString.Lazy (pack, unpack)

import Tenkei
import Pointers

foreign import ccall "wrapper" cborFunctionToPtr
  :: (Ptr Word8 -> CSize -> Ptr (Ptr Word8) -> Ptr CSize -> IO ()) ->
  IO
    (FunPtr
       (Ptr Word8 -> CSize -> Ptr (Ptr Word8) -> Ptr CSize -> IO ()))

foreign import ccall "dynamic" cborPtrToFunction
  :: FunPtr
  (Ptr () -> Ptr Word8 -> CSize -> Ptr (Ptr Word8) -> Ptr CSize -> IO ())
  -> (Ptr () -> Ptr Word8 -> CSize -> Ptr (Ptr Word8) -> Ptr CSize -> IO ())

foreign import ccall "wrapper" cborFunctionPtrToPtr
  :: (CSize -> Ptr Word8 -> CSize -> Ptr (Ptr Word8) -> Ptr CSize -> IO ()) ->
  IO
    (FunPtr
       (CSize -> Ptr Word8 -> CSize -> Ptr (Ptr Word8) -> Ptr CSize -> IO ()))

foreign import ccall "wrapper" freeFunctionToPtr :: (Ptr Word8 -> CSize -> IO ()) -> IO (FunPtr (Ptr Word8 -> CSize -> IO ()))

tenkeiFree :: Ptr Word8 -> CSize -> IO ()
tenkeiFree args _ = free args

tenkeiFreePtr :: FunPtr (Ptr Word8 -> CSize -> IO ())
tenkeiFreePtr = unsafePerformIO $ freeFunctionToPtr tenkeiFree

cborToBinary :: CBOR -> [Word8]
cborToBinary = unpack . runPut . putCBOR

binaryToCBOR :: [Word8] -> CBOR
binaryToCBOR = runGet getCBOR . pack

callCBORIO :: (Ptr Word8 -> CSize -> Ptr (Ptr Word8) -> Ptr CSize -> IO ()) -> (Ptr Word8 -> CSize -> IO ()) -> CBOR -> IO CBOR
callCBORIO function freeFunction input =
  let bytes = cborToBinary input
   in withArray bytes $ \ptr ->
        (alloca
           (\res_ptr ->
              alloca
                (\res_size -> do
                   function ptr (fromIntegral $ length bytes) res_ptr res_size
                   res_ptr' <- peek res_ptr
                   res_size' <- peek res_size
                   res <- peekArray (fromEnum res_size') res_ptr'
                   freeFunction res_ptr' res_size'
                   return $ binaryToCBOR res)))

callCBOR :: (Ptr Word8 -> CSize -> Ptr (Ptr Word8) -> Ptr CSize -> IO ()) -> (Ptr Word8 -> CSize -> IO ()) -> CBOR -> CBOR
callCBOR function freeFunction input = unsafePerformIO $ callCBORIO function freeFunction input

callIO ::
     (Tenkei a, Tenkei b) => (Ptr Word8 -> CSize -> Ptr (Ptr Word8) -> Ptr CSize -> IO ()) -> (Ptr Word8 -> CSize -> IO ()) -> a -> IO b
callIO function freeFunction input = fmap deserialize $ callCBORIO function freeFunction $ serialize input

call :: (Tenkei a, Tenkei b) => (Ptr Word8 -> CSize -> Ptr (Ptr Word8) -> Ptr CSize -> IO ()) -> (Ptr Word8 -> CSize -> IO ()) -> a -> b
call f freeFunction = unsafePerformIO . callIO f freeFunction

offerCBOR :: (CBOR -> CBOR) -> Ptr Word8 -> CSize -> Ptr (Ptr Word8) -> Ptr CSize -> IO ()
offerCBOR f args argn res resn = do
  bytes <- peekArray (fromEnum argn) args
  let x = cborToBinary $ f $ binaryToCBOR bytes
  poke resn $ fromIntegral $ length x
  res_ptr <- newArray x
  poke res res_ptr

-- Throw away the data for function pointers
offerCBORPtr :: (CBOR -> CBOR) -> CSize -> Ptr Word8 -> CSize -> Ptr (Ptr Word8) -> Ptr CSize -> IO ()
offerCBORPtr f d = offerCBOR f

callCBORPtr :: Ptr () -> (Ptr () -> Ptr Word8 -> CSize -> Ptr (Ptr Word8) -> Ptr CSize -> IO ()) -> (Ptr Word8 -> CSize -> IO ()) -> CBOR -> CBOR
callCBORPtr d f = callCBOR (f d)

offer :: (Tenkei a, Tenkei b) => (a -> b) -> Ptr Word8 -> CSize -> Ptr (Ptr Word8) -> Ptr CSize -> IO ()
offer f = offerCBOR $ serialize . f . deserialize

toPointer :: a -> IO TenkeiPtr
toPointer = fmap (TenkeiPtr . castStablePtrToPtr) . newStablePtr

toFunPointer :: (CBOR -> CBOR) -> IO TenkeiFunPtr
toFunPointer = (fmap toTenkeiFunPtr) . cborFunctionPtrToPtr . offerCBORPtr
  where
    toTenkeiFunPtr :: FunPtr a -> TenkeiFunPtr
    toTenkeiFunPtr f = TenkeiFunPtr (TenkeiPtr $ castFunPtrToPtr f) (TenkeiPtr $ castFunPtrToPtr tenkeiFreePtr) $ TenkeiPtr nullPtr

fromPointer :: TenkeiPtr -> IO a
fromPointer x = do
  let stable = castPtrToStablePtr $ getPtr x
  contents <- deRefStablePtr stable
  freeStablePtr stable
  return contents

fromFunPointer :: TenkeiFunPtr -> CBOR -> CBOR
fromFunPointer f = callCBORPtr (getPtr $ dataPtr f) (cborPtrToFunction $ castPtrToFunPtr $ getPtr $ funPtr f) (\_ _ -> return ()) -- this leaks memory! Replace by freePtr later!

toPointerF :: (Traversable f) => f a -> IO (f TenkeiPtr)
toPointerF = traverse toPointer
