module Language.CSPM.LexHelper
(
   lexInclude
  ,lexPlain
  ,filterIgnoredToken
  ,tokenIsIgnored
  ,tokenIsComment
)
where

import qualified Language.CSPM.Lexer as Lexer (scanner)
import Language.CSPM.Token (Token(..), LexError(..))
import Language.CSPM.TokenClasses (PrimToken(..))
import qualified Data.Set as Set
--import qualified Language.CSPM.Token as Token
--  (Token(..), LexError(..))

{- todo : use an error monad -}

lexInclude :: String -> IO (Either LexError [Token])
lexInclude src = do
  case Lexer.scanner src of
    Left err -> return $ Left err
    Right toks -> do
      tokenIncl <- processIncludeAndReverse toks
      case tokenIncl of
        Left err -> return $ Left err
        Right t -> return $ Right t

lexPlain :: String -> Either LexError [Token]
lexPlain src = fmap reverse $ Lexer.scanner src

processIncludeAndReverse :: [Token] -> IO (Either LexError [Token] )
processIncludeAndReverse tokens = picl_acc tokens []
  where 
  picl_acc ::[Token] ->[Token] -> IO (Either LexError [Token] )
  picl_acc [] acc = return $ Right acc
  picl_acc ((Token _ _ _ L_String fname) : (Token _ _ _ L_Include _) :trest) acc = do
    let fileName = reverse $ tail $ reverse $ tail fname -- remove quotes
    -- putStrLn $ "Including file : " ++ fileName
    input <-readFile fileName
    case Lexer.scanner input of
      Right toks -> do
        new_acc <- picl_acc toks acc
        case new_acc of
          Right t -> picl_acc trest t
          e -> return e
      Left e -> return $ Left e
  picl_acc ((incl@(Token _ _ _ L_Include _)) : _) _ = 
    return $ Left $ LexError {
       lexEPos = tokenStart incl
      ,lexEMsg = "Include without filename" 
      }
  picl_acc (h:rest) acc = picl_acc rest $ h:acc

-- consumes newlines 
soakNewLines :: [Token] -> [Token]
soakNewLines = worker
  where 
    worker [] = []
    worker [x] = case tokenClass x of
       L_NewLine -> []
       _         -> [x] 
    worker (h1:h2:t) = case (tokenClass h1, tokenClass h2) of
       (L_NewLine, L_NewLine) -> worker (h1:t)
       (L_NewLine, _) | isH2NewLineConsumer -> worker $ h2:t
       (L_NewLine, _) -> h1 : worker (h2:t)
       (_, L_NewLine) | isH1NewLineConsumer -> worker $ h1:t
       (_, L_NewLine) -> h1:worker (h2:t)
       _   -> h1:worker (h2:t)
      where
        isH2NewLineConsumer = tokenClass h2 `Set.member` consumeNLBeforeToken
        isH1NewLineConsumer = tokenClass h1 `Set.member` consumeNLAfterToken
    binaryOperators =  Set.fromList [T_is, T_hat, T_hash, T_times, T_slash, 
      T_percent, T_plus, T_minus, T_eq, T_neq,
      T_ge, T_le, T_not, T_amp, T_semicolon,
      T_comma, T_triangle, T_box, T_rhd, T_exp,
      T_sqcap, T_interleave, T_backslash, T_parallel,
      T_mid, T_at, T_atat, T_rightarrow, T_leftarrow,
      T_leftrightarrow, T_dot, T_dotdot, T_exclamation,
      T_questionmark, T_colon, T_openBrack, T_closeBrack,
      T_openOxBrack, T_closeOxBrack,T_openPBrace,
      T_openBrackBrack, T_if, T_then,T_else, T_let, T_and,
      T_or, T_Refine, T_trace,T_failure, T_failureDivergence,
      T_refusalTesting, T_refusalTestingDiv, T_revivalTesting, 
      T_revivalTestingDiv,T_tauPriorityOp, T_within]
    consumeNLBeforeToken = Set.fromList [T_closeParen, T_gt,
                        T_closeBrace, T_closeBrackBrack, T_closePBrace] 
                           `Set.union` binaryOperators
    consumeNLAfterToken =  Set.fromList [T_openParen, T_openBrace, T_lt]
                           `Set.union` binaryOperators

filterIgnoredToken :: [Token] -> [Token]
filterIgnoredToken = filter (not . tokenIsIgnored)

tokenIsIgnored :: Token -> Bool
tokenIsIgnored (Token _ _ _ L_LComment _) = True
tokenIsIgnored (Token _ _ _ L_BComment _) = True
tokenIsIgnored _ = False

tokenIsComment :: Token -> Bool
tokenIsComment (Token _ _ _ L_LComment _) = True
tokenIsComment (Token _ _ _ L_BComment _) = True
tokenIsComment _ = False
