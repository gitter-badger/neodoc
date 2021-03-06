module Language.Docopt.Parser.Desc where

import Prelude
import Data.Functor (($>))
import Control.Alt ((<|>))
import Control.Apply ((*>), (<*))
import Control.MonadPlus (guard)
import Data.List (List, (:), many, head, length, filter)
import Text.Parsing.Parser (ParseError, fail) as P
import Text.Parsing.Parser.Combinators ((<?>), try, choice, lookAhead, manyTill,
                                        option, optionMaybe, notFollowedBy) as P
import Data.Either (Either(..), either)
import Data.Maybe (Maybe(Nothing, Just), isJust, maybe)
import Data.Generic (class Generic, gEq, gShow)
import Data.String (fromChar)
import Data.Array as A
import Data.String.Ext ((^=))

import Language.Docopt.Value (Value, prettyPrintValue)
import Language.Docopt.Parser.Common (sameIndent, markIndent, sameLine, markLine)
import Language.Docopt.Parser.Lexer (lexDescs)
import Language.Docopt.Parser.Lexer as L
import Language.Docopt.Value as Value

data Desc = OptionDesc Option
          | CommandDesc -- XXX: Can be removed now?

data Name = Flag Char | Long String | Full Char String

getFlag :: Name -> Maybe Char
getFlag (Flag c)   = pure c
getFlag (Full c _) = pure c
getFlag _          = Nothing

getName :: Name -> Maybe String
getName (Long   n) = pure n
getName (Full _ n) = pure n
getName _          = Nothing

newtype Argument = Argument {
  name     :: String
, default  :: Maybe Value
, optional :: Boolean
}

runArgument :: Argument -> {
  name     :: String
, default  :: Maybe Value
, optional :: Boolean
}
runArgument (Argument a) = a

newtype Option = Option {
  name       :: Name
, arg        :: Maybe Argument
, env        :: Maybe String
, repeatable :: Boolean
}

data Content
  = Text
  | Default String
  | Env     String

isDefaultTag :: Content -> Boolean
isDefaultTag (Default _) = true
isDefaultTag _           = false

getDefaultValue :: Content -> Maybe Value
getDefaultValue (Default v) = either (const Nothing) Just (Value.parse v true)
getDefaultValue _           = Nothing

isEnvTag :: Content -> Boolean
isEnvTag (Env _) = true
isEnvTag _       = false

getEnvKey :: Content -> Maybe String
getEnvKey (Env k) = Just k
getEnvKey _       = Nothing

derive instance genericDesc     :: Generic Desc
derive instance genericArgument :: Generic Argument
derive instance genericName     :: Generic Name
derive instance genericOption   :: Generic Option
derive instance genericContent  :: Generic Content

instance showDesc :: Show Desc
  where show = gShow

instance showOption :: Show Option
  where show = gShow

instance showArgument :: Show Argument
  where show = gShow

instance showName :: Show Name
  where show = gShow

instance showContent :: Show Content
  where show = gShow

instance eqOption :: Eq Option
  where eq = gEq

instance eqArgument :: Eq Argument
  where eq = gEq

instance eqName :: Eq Name
  where eq = gEq

instance eqDesc :: Eq Desc
  where eq = gEq

prettyPrintDesc :: Desc -> String
prettyPrintDesc (OptionDesc opt) = "Option " ++ prettyPrintOption opt
prettyPrintDesc (CommandDesc) = "Command"

prettyPrintOption :: Option -> String
prettyPrintOption (Option opt)
  = (name opt.name) ++ arg ++ env
  where
      name (Flag c)   = "-" ++ fromChar c
      name (Long n)   = "--" ++ n
      name (Full c n) = "-" ++ fromChar c ++ ", --" ++ n

      arg = maybe "" id do
        (Argument a) <- opt.arg
        return $
          (if a.optional then "[" else "")
            ++ "=" ++ a.name
            ++ (if a.optional then "]" else "")
            ++ (if opt.repeatable then "..." else "")
            ++ (maybe ""
                      (\v -> "[default: " ++ prettyPrintValue v ++ "]")
                      a.default)

      env = maybe "" id do
        k <- opt.env
        return $ " [env: " ++ k ++ "]"

prettyPrintArgument :: Argument -> String
prettyPrintArgument (Argument { optional: o, name: n, default: d })
  = (if o then "[" else "") ++ n ++ (if o then "]" else "")
    ++ maybe "" (\v -> " [default: " ++ (prettyPrintValue v) ++  "]") d

argument :: String
         -> Boolean
         -> Maybe Value
         -> Argument
argument name optional default = Argument { name:   name
                                          , default:  default
                                          , optional: optional
                                          }

run :: String -> Either P.ParseError (List Desc)
run x = lexDescs x >>= parse

parse :: (List L.PositionedToken) -> Either P.ParseError (List Desc)
parse = flip L.runTokenParser descParser

descParser :: L.TokenParser (List Desc)
descParser =
  markIndent do
    opt  <- option
    opts <- many $ sameIndent *> option
    return (opt : opts)
  where

    anyName :: L.TokenParser String
    anyName = L.angleName <|> L.shoutName <|> L.name

    option :: L.TokenParser Desc
    option = do
      xopt@(Option opt) <- start

      description <- do
        flip P.manyTill (L.eof <|> (P.lookAhead $ P.try $ void start)) do
          P.choice $ P.try <$> [
            Default <$> L.tag "default"
          , Env     <$> L.tag "env"
          , L.anyToken *> pure Text
          ]

      let defaults = getDefaultValue <$> filter isDefaultTag description
          envs     = getEnvKey       <$> filter isEnvTag     description

      if (length defaults > 1)
         then P.fail $
          "Option " ++ (show $ prettyPrintOption xopt)
                    ++ " has multiple defaults!"
         else return unit

      if (length envs > 1)
         then P.fail $
          "Option " ++ (show $ prettyPrintOption xopt)
                    ++ " has multiple environment mappings!"
         else return unit

      let default = head defaults >>= id
          env     = head envs     >>= id

      if (isJust default) && (not $ isJust opt.arg)
         then P.fail $
          "Option " ++ (show $ prettyPrintOption xopt)
                    ++ " does not take arguments. "
                    ++ "Cannot specify defaults."
         else return unit

      return $ OptionDesc $ Option $
        opt { env = env
            , arg = do
                (Argument arg) <- opt.arg
                return $ Argument $ arg {
                  default = default
                }
            }

      where

        start :: L.TokenParser Option
        start = do
          P.choice $ P.try <$> [
            short <* do
              P.notFollowedBy do
                P.choice $ P.try <$> [ L.comma *> long, long ]
          , long <* do
              P.notFollowedBy do
                P.choice $ P.try <$> [ L.comma *> short, short ]
          , both
          ]

        short :: L.TokenParser Option
        short = do
          opt <- sopt

          -- Grab the adjacent positional-looking argument
          -- in case the token did not have an explicit
          -- binding via `=`.
          arg <- maybe
                  (P.optionMaybe do
                    n <- L.shoutName <|> L.angleName
                    return { name: n, optional: false }
                  )
                  (return <<< Just)
                  opt.arg

          repeatable <- P.option false (L.tripleDot $> true)

          return $ Option { name: Flag opt.flag
                          , arg:  Argument <$> do
                              a <- arg
                              return {
                                name:       a.name
                              , optional:   a.optional
                              , default:    Nothing
                              }
                          , env:        Nothing
                          , repeatable: repeatable
                          }

        long :: L.TokenParser Option
        long = do
          opt <- lopt

          -- Grab the adjacent positional-looking argument
          -- in case the token did not have an explicit
          -- binding via `=`.
          arg <- maybe
                  (P.optionMaybe do
                    n <- L.shoutName <|> L.angleName
                    return { name: n, optional: false }
                  )
                  (return <<< Just)
                  opt.arg

          repeatable <- P.option false (L.tripleDot $> true)

          return $ Option { name: Long opt.name
                          , arg:  Argument <$> do
                              a <- arg
                              return {
                                name:       a.name
                              , optional:   a.optional
                              , default:    Nothing
                              }
                          , env:        Nothing
                          , repeatable: repeatable
                          }

        both :: L.TokenParser Option
        both = markLine do
          x <- short
          y <- do sameLine
                  P.choice $ P.try <$> [ L.comma *> long
                                       , long
                                       ]
          combine x y

          where
            -- Combine two options into one. This function *does not* cover all
            -- cases right now. It deals only with a known subset and can there-
            -- fore make assumptions
            combine :: Option -> Option -> L.TokenParser Option
            combine (Option x@{ name: Flag f }) (Option y@{ name: Long n }) = do
              either P.fail return do
                arg <- combineArg x.arg y.arg
                return $ Option {
                  name:       Full f n
                , arg:        arg
                , env:        Nothing -- No need to keep at this stage
                , repeatable: x.repeatable || y.repeatable
                }
              where
                combineArg (Just (Argument a)) (Just (Argument a'))
                  | (a.name ^= a'.name) = return $ Just
                      $ Argument { name:     a.name
                                 , optional: a.optional || a'.optional
                                 , default:  a.default <|> a'.default
                                 }
                combineArg Nothing  (Just b) = return (pure b)
                combineArg (Just a) Nothing  = return (pure a)
                combineArg Nothing Nothing   = return Nothing
                combineArg (Just a) (Just b) = Left $
                        "Arguments mismatch: " ++ (show $ prettyPrintArgument a)
                                    ++ " and " ++ (show $ prettyPrintArgument b)
            combine _ _ = P.fail "Invalid case - expected flag and long option"

    sopt :: L.TokenParser { flag :: Char, arg :: Maybe { name :: String
                                                       , optional :: Boolean
                                                       } }
    sopt = do
      opt <- L.sopt
      (guard $ (A.length opt.stack == 0)) P.<?> "No stacked options"
      return { flag: opt.flag, arg: opt.arg }

    lopt :: L.TokenParser { name :: String, arg :: Maybe { name :: String
                                                         , optional :: Boolean
                                                         } }
    lopt = L.lopt
