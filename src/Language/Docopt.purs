module Language.Docopt (
  module D
, runDocopt
) where

import Prelude
import Debug.Trace
import Data.Either (either, Either(..))
import Data.Maybe (maybe, Maybe(..))
import Data.List (toList, List(..), concat)
import Data.Foldable (intercalate)
import Data.Monoid (Monoid)
import Data.String (fromChar)
import Data.Map (Map(..))
import qualified Data.Map as Map
import Control.Apply ((*>))
import Data.Bifunctor (lmap)
import Data.Traversable (traverse)

import qualified Language.Docopt.Types     as D
import qualified Language.Docopt.Pretty    as D
import qualified Language.Docopt.ParserGen as Gen

import qualified Language.Docopt.Parser.Scanner as Scanner
import qualified Language.Docopt.Parser.Usage as Usage
import qualified Language.Docopt.Parser.Desc as Desc
import qualified Language.Docopt.Solver as Solver

import qualified Text.Parsing.Parser as P

import Text.Wrap (dedent)

runDocopt :: String
          -> Array String
          -> Either D.DocoptError (Map D.Argument D.Value)
runDocopt docopt argv = do
  docopt <- toScanErr  $ Scanner.scan $ dedent docopt
  us     <- toParseErr $ Usage.run docopt.usage
  ds     <- toParseErr $ concat <$> Desc.run `traverse` docopt.options
  solved <- toSolveErr $ Solver.solve us ds
  toParseErr $ Gen.runParser (toList argv)
                             (Gen.genParser solved)

toScanErr :: forall a. Either P.ParseError a -> Either D.DocoptError a
toScanErr  = lmap D.DocoptScanError

toParseErr :: forall a. Either P.ParseError a -> Either D.DocoptError a
toParseErr = lmap D.DocoptParseError

toSolveErr :: forall a. Either D.SolveError a -> Either D.DocoptError a
toSolveErr = lmap D.DocoptSolveError