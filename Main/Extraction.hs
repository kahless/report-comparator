-- Извлечение адресов из файлов и их разбор
module Main.Extraction where


import Control.Monad
import Text.Regex.PCRE ((=~))
import System.FilePath (takeBaseName)
import System.Directory (getDirectoryContents)
import Text.Parsec.Error (ParseError)
import System.IO

import Address.Main
import Address.Types
import ParseCSV


-- Извлекает адреса из таблицы отчёта в заданном файле
fromNotes :: String -> IO [String]
fromNotes file = liftM parseCSV (readFile' utf8 file)
             >>= either (return . error . show) (return . pick)
    where pick lines = lines >>=
              \l -> if head l =~ "\\d+" -- Если в первой ячейке номер строки,
                    then [l!!2]         -- то адрес лежит в 3-й ячейке.
                    else []             -- Иначе строка не содержит адрес.
          readFile' enc name = openFile name ReadMode
                           >>= (flip hSetEncoding $ enc) >&&> hGetContents
              where (>&&>) = liftM2 (>>)



-- Извлекает адреса из имён файлов фотографий в заданном каталоге
fromPhotos :: String -> IO [String]
fromPhotos dir = liftM
    (map takeBaseName . filter (`notElem` [ ".", ".." ]))
    (getDirectoryContents dir)


-- Извлекает адреса с помощью пользовательской функции из заданного файла и 
-- возвращает список пар, где в каждой паре строка адреса и результат её 
-- разбора.
extract :: (String -> IO [String])
        -> String
        -> IO [ (String, Either ParseError [Component]) ]
extract extracter f = do
    strings  <- extracter f -- Извлекаю адреса
    let parsed = map parseAddr strings -- Анализирую адреса
    return $ zip strings parsed
        -- Возвращаю комбинацию строки адреса и результата её разбора