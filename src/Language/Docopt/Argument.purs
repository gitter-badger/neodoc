module Language.Docopt.Argument (
    Argument (..)
  , IsRepeatable ()
  , Branch (..)
  , IsOptional ()
  , IsRepeatable ()
  , prettyPrintBranch
  , prettyPrintArg
  , runBranch
  , isRepeatable
  , hasDefault
  , getEnvKey
  , hasEnvBacking
  , takesArgument
  , isOption
  , isFlag
  , opt',   opt,   optR,   opt_,   optR_
  , lopt',  lopt,  loptR,  lopt_,  loptR_
  , sopt',  sopt,  soptR,  sopt_,  soptR_
  ,         optE,  optER,  optE_,  optER_
  , loptE', loptE, loptER, loptE_, loptER_
  , soptE', soptE, soptER, soptE_, soptER_
  ) where

import Prelude
import Data.Maybe (Maybe(..), maybe)
import Data.List (List())
import Data.Foldable (intercalate)
import Data.String as Str
import Data.Function (on)
import Data.String (fromChar)
import Data.String.Ext ((^=))
import Control.Apply ((*>))

import Language.Docopt.Value (Value(..), prettyPrintValue)
import Language.Docopt.Option as O
import Language.Docopt.Env as Env
import Language.Docopt.Env (Env())

type IsRepeatable = Boolean
type IsOptional = Boolean

newtype Branch = Branch (List Argument) -- XXX: Move to type alias

runBranch :: Branch -> List Argument
runBranch (Branch xs) = xs

data Argument
  = Command     String
  | Positional  String IsRepeatable
  | Option      O.Option
  | Group       IsOptional (List Branch) IsRepeatable
  | EOA
  | Stdin

instance showBranch :: Show Branch where
  show (Branch xs) = "Branch " ++ show (show <$> xs)

instance eqBranch :: Eq Branch where
  eq (Branch xs) (Branch xs') = (xs == xs')

instance showArgument :: Show Argument where
  show (EOA) = "EOA"
  show (Stdin) = "Stdin"
  show (Command n)
    = intercalate " " [ "Command", show n ]
  show (Positional n r)
    = intercalate " " [ "Positional", show n, show r ]
  show (Group o bs r) 
    = intercalate " " [ "Group", show o, show bs, show r ]
  show (Option o) = "Option " ++ show o

instance ordArgument :: Ord Argument where
  -- XXX: Implement a more efficient `compare` function
  compare = compare `on` show

instance eqArgument :: Eq Argument where
  eq (EOA) (EOA) = true
  eq (Stdin) (Stdin) = true
  eq (Command n) (Command n') = (n == n')
  eq (Positional n r) (Positional n' r') = (n ^= n') && (r == r')
  eq (Group o bs r) (Group o' bs' r') = (o == o') && (bs == bs') && (r == r')
  eq (Option o) (Option o') = o == o'
  eq _ _ = false

prettyPrintBranch :: Branch -> String
prettyPrintBranch (Branch xs) = intercalate " " (prettyPrintArg <$> xs)

prettyPrintArg :: Argument -> String
prettyPrintArg (Stdin)             = "-"
prettyPrintArg (EOA)               = "-- ARGS..."
prettyPrintArg (Command name)      = name
prettyPrintArg (Positional name r) = name ++ (if r then "..." else "")
prettyPrintArg (Option o)          = O.prettyPrintOption o
prettyPrintArg (Group o bs r)      = open ++ inner ++ close ++ repetition
  where
    open       = if o then "[" else "("
    close      = if o then "]" else ")"
    inner      = intercalate " | " (prettyPrintBranch <$> bs)
    repetition = if r then "..." else ""

isRepeatable :: Argument -> Boolean
isRepeatable (Option o)       = O.isRepeatable o
isRepeatable (Positional _ r) = r
isRepeatable _                = false

hasDefault :: Argument -> Boolean
hasDefault (Option o) = O.hasDefault o
hasDefault _          = false

takesArgument :: Argument -> Boolean
takesArgument (Option o) = O.takesArgument o
takesArgument _          = false

getEnvKey :: Argument -> Maybe String
getEnvKey (Option (O.Option o)) = o.env
getEnvKey _                     = Nothing

hasEnvBacking :: Argument -> Env -> Boolean
hasEnvBacking p env = maybe false id $ flip Env.member env <$> getEnvKey p

isFlag :: Argument -> Boolean
isFlag (Option o) = O.isFlag o
isFlag _          = false

isOption :: Argument -> Boolean
isOption (Option _) = true
isOption _          = false

--------------------------------------------------------------------------------
-- Short hand option creation
--------------------------------------------------------------------------------

-- short hand to create an Option argument
opt' :: Maybe O.Flag
     -> Maybe O.Name
     -> Maybe O.Argument
     -> Maybe String
     -> IsRepeatable
     -> Argument
opt' f n a e r = Option $ O.opt' f n a e r

opt :: O.Flag -> O.Name -> O.Argument -> Argument
opt f n a = Option $ O.opt f n a

optR :: O.Flag -> O.Name -> O.Argument -> Argument
optR f n a = Option $ O.optR f n a

opt_ :: O.Flag -> O.Name -> Argument
opt_ f n = Option $ O.opt_ f n

optR_ :: O.Flag -> O.Name -> Argument
optR_ f n = Option $ O.optR_ f n

-- short hand to create an Short-Option argument
sopt' :: O.Flag -> (Maybe O.Argument) -> IsRepeatable -> Argument
sopt' f a r = Option $ O.sopt' f a r

sopt :: O.Flag -> O.Argument -> Argument
sopt f a = Option $ O.sopt f a

soptR :: O.Flag -> O.Argument -> Argument
soptR f a = Option $ O.soptR f a

sopt_ :: O.Flag -> Argument
sopt_ f = Option $ O.sopt_ f

soptR_ :: O.Flag -> Argument
soptR_ f = Option $ O.soptR_ f

-- short hand to create an Long-Option argument
lopt' :: O.Name -> (Maybe O.Argument) -> IsRepeatable -> Argument
lopt' n a r = Option $ O.lopt' n a r

lopt :: O.Name -> O.Argument -> Argument
lopt n a = Option $ O.lopt n a

loptR :: O.Name -> O.Argument -> Argument
loptR n a = Option $ O.loptR n a

lopt_ :: O.Name -> Argument
lopt_ n = Option $ O.lopt_ n

loptR_ :: O.Name -> Argument
loptR_ n = Option $ O.loptR_ n

--------------------------------------------------------------------------------
-- Short hand option creation (with env tag)
--------------------------------------------------------------------------------

optE :: O.Flag -> O.Name -> O.Argument -> String -> Argument
optE f n a e = Option $ O.optE f n a e

optER :: O.Flag -> O.Name -> O.Argument -> String -> Argument
optER f n a e = Option $ O.optER f n a e

optE_ :: O.Flag -> O.Name -> String -> Argument
optE_ f n e = Option $ O.optE_ f n e

optER_ :: O.Flag -> O.Name -> String -> Argument
optER_ f n e = Option $ O.optER_ f n e

-- short hand to create an Short-Option argument
soptE' :: O.Flag -> (Maybe O.Argument) -> IsRepeatable -> String -> Argument
soptE' f a r e = Option $ O.soptE' f a r e

soptE :: O.Flag -> O.Argument -> String -> Argument
soptE f a e = Option $ O.soptE f a e

soptER :: O.Flag -> O.Argument -> String -> Argument
soptER f a e = Option $ O.soptER f a e

soptE_ :: O.Flag -> String -> Argument
soptE_ f e = Option $ O.soptE_ f e

soptER_ :: O.Flag -> String -> Argument
soptER_ f e = Option $ O.soptER_ f e

-- short hand to create an Long-Option argument
loptE' :: O.Name -> (Maybe O.Argument) -> IsRepeatable -> String -> Argument
loptE' n a r e = Option $ O.loptE' n a r e

loptE :: O.Name -> O.Argument -> String -> Argument
loptE n a e = Option $ O.loptE n a e

loptER :: O.Name -> O.Argument -> String -> Argument
loptER n a e = Option $ O.loptER n a e

loptE_ :: O.Name -> String -> Argument
loptE_ n e = Option $ O.loptE_ n e

loptER_ :: O.Name -> String -> Argument
loptER_ n e = Option $ O.loptER_ n e
