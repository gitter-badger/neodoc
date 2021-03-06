-- | ARGV lexer
-- |
-- | > Given an argv array, i.e. `process.argv`, derive a stream of tokens
-- | > suitable for parsing against a docopt specification.
-- |
-- | ===

module Language.Docopt.ParserGen.Lexer (
  lex
  ) where

import Prelude
import Debug.Trace
import Data.Either (Either())
import Data.Maybe (Maybe(..))
import Control.Apply ((*>), (<*))
import Control.Alt ((<|>))
import Data.String (fromCharArray)
import Data.List (List(..), singleton, many)
import Text.Parsing.Parser (ParseError, Parser, runParser) as P
import Text.Parsing.Parser.Combinators (try, choice, optional, optionMaybe) as P
import Text.Parsing.Parser.Pos (Position(Position)) as P
import Text.Parsing.Parser.String (eof, anyChar, char, oneOf, noneOf, string) as P
import Data.Array as A
import Control.Plus (empty)
import Language.Docopt.ParserGen.Token (PositionedToken(..), Token(..))
import Language.Docopt.Parser.Base (space, alphaNum)
import Language.Docopt.Value (Value(..)) as D

-- | Parse a single token from the ARGV stream.
-- | Because each item on the ARGV stream is a a string itself, apply a parser
-- | to each item and derive a token.
parseToken :: P.Parser String Token
parseToken = do
  P.choice $ P.try <$> [
    stdin <* P.eof
  , sopt  <* P.eof
  , lopt  <* P.eof
  , eoa   <* P.eof
  , lit   <* P.eof
  ]

  where
    stdin :: P.Parser String Token
    stdin = do
      P.char '-'
      P.eof
      return $ Stdin

    eoa :: P.Parser String Token
    eoa = do
      P.string "--"
      P.eof
      return $ EOA empty

    -- | Parse a short option
    sopt :: P.Parser String Token
    sopt = do
      P.char '-'
      x   <- alphaNum
      xs  <- A.many $ P.noneOf [ '=' ]
      arg <- P.optionMaybe arg
      P.eof
      return $ SOpt x xs arg

    -- | Parse a long option
    lopt :: P.Parser String Token
    lopt = do
      P.string "--"
      xs <- fromCharArray <$> do
        A.some $ P.noneOf [ '=' ]
      arg <- P.optionMaybe arg
      P.eof
      pure $ LOpt xs arg

    -- | Parse a literal
    lit :: P.Parser String Token
    lit = Lit <<< fromCharArray <$> do
      A.many P.anyChar

    arg = do
      P.char '='
      fromCharArray <$> A.many P.anyChar

-- | Reduce the array of arguments (argv) to a list of tokens, by parsing each
-- | item individually.
lex :: (List String) -> Either P.ParseError (List PositionedToken)
lex xs = go xs 1
  where
    go Nil _ = return Nil
    go (Cons x xs) n = do
      tok <- P.runParser x parseToken
      case tok of
        (EOA _) -> do
          return $ singleton $ PositionedToken {
            token:     EOA (D.StringValue <$> xs)
          , sourcePos: P.Position { line: 1, column: n }
          , source:    x
          }
        _ -> do
          toks <- go xs (n + 1)
          return
            $ singleton (PositionedToken {
                          token:     tok
                        , sourcePos: P.Position { line: 1, column: n }
                        , source:    x
                        }) ++ toks
