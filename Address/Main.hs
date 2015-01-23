module Address.Main where


import Address.Types
import qualified Address.Digit as D
import qualified Address.Symbol as S
import Text.Parsec
import Control.Applicative hiding (optional, (<|>), many)
import Debug.Trace (trace)


parseAddr = parse address ""


address = many space *> component `sepEndBy` sep <* eof
    where sep = optional (char ',' <|> char '.') *> many space


component = try D.prefix
        <|> try S.prefix
        <|> try D.postfix
        <|>     S.postfix
