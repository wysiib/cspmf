----------------------------------------------------------------------------
-- |
-- Module      :  Language.CSPM.AlexWrapper
-- 
-- Stability   :  experimental
-- Portability :  GHC-only
--
-- Wrapper functions for Alex

{-# LANGUAGE RecordWildCards #-}
module Language.CSPM.AlexWrapper
where

import Language.CSPM.Token
import Language.CSPM.TokenClasses
import Language.CSPM.UnicodeSymbols as UnicodeSymbols (lookupToken)

import Data.Char
import Data.List
import Control.Monad

type AlexInput
  = (AlexPosn     -- current position
    ,Char         -- previous char
    ,String)      -- current input string

data AlexState = AlexState {
   alex_pos :: !AlexPosn -- position at current input location
  ,alex_inp :: String	-- the current input
  ,alex_chr :: !Char	-- the character before the input
  ,alex_scd :: !Int 	-- the current startcode
  ,alex_cnt :: !Int 	-- number of tokens
  }

runAlex :: String -> Alex a -> Either LexError a
runAlex input (Alex f) 
  = case f initState of
     Left msg -> Left msg
     Right ( _, a ) -> Right a
  where
    initState
      = AlexState {
       alex_pos = alexStartPos
      ,alex_inp = input
      ,alex_chr = '\n'
      ,alex_scd = 0
      ,alex_cnt = 0
      }

newtype Alex a = Alex { unAlex :: AlexState -> Either LexError (AlexState, a) }

instance Monad Alex where
  m >>= k  = Alex $ \s -> case unAlex m s of
                            Left msg -> Left msg
                            Right (s',a) -> unAlex (k a) s'
  return a = Alex $ \s -> Right (s,a)

alexGetInput :: Alex AlexInput
alexGetInput
 = Alex $ \s@AlexState{alex_pos=pos, alex_chr=c, alex_inp=inp} ->
         Right (s, (pos,c,inp))

alexSetInput :: AlexInput -> Alex ()
alexSetInput (pos, c, inp)
 = Alex $ \state -> case state {alex_pos=pos,alex_chr=c,alex_inp=inp} of
            s@(AlexState{}) -> Right (s, ())

alexError :: String -> Alex a
alexError message = Alex $ update where
    update st = Left $ LexError {lexEPos = alex_pos st, lexEMsg = message }

alexGetStartCode :: Alex Int
alexGetStartCode = Alex $ \s@AlexState{alex_scd=sc} -> Right (s, sc)

alexSetStartCode :: Int -> Alex ()
alexSetStartCode sc = Alex $ \s -> Right (s{alex_scd=sc}, ())

-- increase token counter and return tokenCount
alexCountToken :: Alex Int
alexCountToken
  = Alex $ \s -> Right (s {alex_cnt = succ $ alex_cnt s}, alex_cnt s)

alexGetChar :: AlexInput -> Maybe (Char, AlexInput)
alexGetChar (_p, _c, []) = Nothing
alexGetChar (p, _c, (c:s))
  = let p' = alexMove p c
    in p' `seq` Just (adj_c, (p', adj_c, s))
   where
     adj_c | c == '\xac' = '\x04' -- special case for the not operator
           | c <= '\xff' = c
           | otherwise = '\x04'
-- -----------------------------------------------------------------------------
-- Useful token actions

type AlexAction result = AlexInput -> Int -> result

-- perform an action for this token, and set the start code to a new value
--andBegin :: AlexAction result -> Int -> AlexAction result
--andBegin action code input len = do alexSetStartCode code; action input len

--token :: (String -> Int -> token) -> AlexAction token
--token t input len = return (t input len)

-- after the dfa calls mkL, we copy the position and string to the token
mkL :: PrimToken -> AlexInput -> Int -> Alex Token
mkL c (pos,_ , str) len = do
  cnt <- alexCountToken
  return $ Token {
    tokenId     = mkTokenId cnt
  , tokenStart  = pos
  , tokenLen    = len
  , tokenClass  = c
  , tokenString = take len str
  }

mk_Unicode_Token :: AlexInput -> Int -> Alex Token
mk_Unicode_Token (pos,_ , str) len = do
  when (len /= 1) $ error "internal error unicode symbol length not 1"
  let symbol = head str
  case UnicodeSymbols.lookupToken symbol of
    Nothing -> lexError $ "unknown Unicode symbol : " ++ [symbol]
    Just tokenClass -> do
      cnt <- alexCountToken
      return $ Token {
         tokenId     = mkTokenId cnt
       , tokenStart  = pos
       , tokenLen    = 1
       , tokenClass  = tokenClass
       , tokenString = [symbol]
       }

block_comment :: AlexInput -> Int -> Alex Token
block_comment (startPos, _ , '\123':'-':input) 2 = do
    case go 1 "-{" input of
      Nothing -> Alex $ \_-> Left $ LexError {
         lexEPos = startPos
        ,lexEMsg = "Unclosed Blockcomment"
        }
      Just (acc, rest) -> do
        cnt <- alexCountToken
        let
          tokenId = mkTokenId cnt
          tokenString = reverse acc
          tokenLen = length tokenString
          tokenStart = startPos
          tokenClass = case (tokenString, acc) of
               ('\123':'-':'#':_, '\125':'-':'#':_) ->  L_Pragma
               ('\123':'-':_    , '\125':'-':_    ) ->  L_BComment
        alexSetInput (foldl' alexMove startPos tokenString, '\125', rest)
        return $ Token {..}
  where
    go 0 acc rest = Just (acc, rest)
    go nested acc rest = case rest of
      '-' : '\125' : r2 -> go (pred nested) ('\125': '-' : acc) r2
      '\123' : '-'  : r2 -> go (succ nested) ('-'  : '\123': acc) r2
      h:r2 -> go nested (h : acc) r2
      [] -> Nothing

lexError :: String -> Alex a
lexError s = do
  (_p,_c,input) <- alexGetInput
  let
    pos = if not $ null input
            then " at " ++ (showChar $ head input)
            else " at end of file"
  alexError $ s ++ pos
  where
    showChar c =
     if isPrint c
       then show c
       else "charcode " ++ (show $ ord c)

alexEOF :: Alex Token
alexEOF = return (Token (mkTokenId 0) (AlexPn 0 0 0) 0 L_EOF "")

{- reverenced from Code generated by Alex -}

alexInputPrevChar :: AlexInput -> Char
alexInputPrevChar (_p, c, _s) = c
