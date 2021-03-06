module Parsers.GeneralParsers where

import Data.Char
import Data.Either

import Text.Megaparsec
import Text.Megaparsec.Char

import Types

type Parser = Parsec () String

allowedCharacterLower :: Parser Char
allowedCharacterLower = lowerChar <|> digitChar

allowedCharacterUpper :: Parser Char
allowedCharacterUpper = upperChar <|> digitChar

lowerWord :: Parser String
lowerWord = some allowedCharacterLower

upperWord :: Parser String
upperWord = do
  c <- allowedCharacterUpper
  cs <- many allowedCharacterLower
  return $ toLower c : cs

allCapsWord :: Parser String
allCapsWord = fmap toLower <$> many allowedCharacterUpper

pascalCaseIdentifier :: Parser Identifier
pascalCaseIdentifier = some upperWord

camelCaseIdentifier :: Parser Identifier
camelCaseIdentifier = do
  initial <- lowerWord
  rest <- many upperWord
  return (initial : rest)

snakeCaseIdentifier :: Parser Identifier
snakeCaseIdentifier = sepBy1 lowerWord $ char '_'

camelCaseToIdentifier :: String -> Identifier
camelCaseToIdentifier s = fromRight (error "This should not be happening!") $ parse camelCaseIdentifier "" s

pascalCaseToIdentifier :: String -> Identifier
pascalCaseToIdentifier s = fromRight (error "This should not be happening!") $ parse pascalCaseIdentifier "" s
