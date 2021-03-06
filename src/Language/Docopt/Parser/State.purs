module Language.Docopt.Parser.State where

import Prelude

type ParserState = {
  indentation :: Int -- The active indentation level
, line        :: Int -- The active line
}
