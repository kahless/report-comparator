-- Извлечение адресов из файлов и их разбор
module Data.Extraction where


import Debug.Trace (trace)
import Control.Monad
import System.FilePath (takeFileName, takeBaseName)
import System.Directory (getDirectoryContents, doesDirectoryExist)
import Text.Parsec.Error (ParseError)
import System.IO
import Control.Exception (throwIO)
import System.IO.Error (userError)
import System.Environment (getEnvironment)
import System.Process
import Text.Regex.TDFA
import Data.List (intercalate)
import Data.List.Split (splitOn)

import Paths_report_comparator
import Data.Types
import Address.Main
import Address.Types


-- Утилита для получения стандартного вывода из дочернего процесса. Создавалась 
-- специально для питона, чтобы принудить его писать в utf-8, так как в windows 
-- питон сбоит из-за того, что не умеет писать в дефолтной системной кодировке.
pythonStdout :: CreateProcess -> IO String
pythonStdout conf = do
   env <- getEnvironment
   (_, Just outH, _, _) <- createProcess conf
      {
         std_out = CreatePipe
      ,  env = Just (("PYTHONIOENCODING", "utf_8"):env)
      }
   hSetEncoding outH utf8
   hGetContents outH


-- Извлекает адреса из имён файлов внутри каталога с фотографиями. Может 
-- работать в двух режимах: извлечение из имён каталогов и из имён обычных 
-- файлов.
fromPhotos :: Bool -> FilePath -> IO [Address]
fromPhotos dirMode dir = do

   dirContents <- getDirectoryContents dir
   let files = [ file
               | name <- dirContents
               , name /= "."
               , name /= ".."
               , let file = dir ++ "/" ++ name
               ]

   hasSubDirs <- (not . null) `liftM` (doesDirectoryExist `filterM` files)

   if hasSubDirs
   then concat `liftM` (fromPhotos dirMode `mapM` files)
   else if dirMode
        then
           -- Если в каталоге нет ни одного подкаталога,
           -- значит имя каталога содержит искомый адрес.
           let name = takeFileName dir
           in return [ Address name name dir ]
        else
           -- Если в каталоге нет ни одного подкаталога, значит адреса 
           -- содержатся в непосредственном содержимом каталога.
           return [ Address name name file
                  | file <- files
                  , let name = cropCopy (takeBaseName file)
                  ]

   where cropCopy name = name'
            where (name', _, _) = name =~ " \\([[:digit:]]+\\)\
                                         \| - Copy \\([[:digit:]]+\\)\
                                         \| - Копия \\([[:digit:]]+\\)"
                                         :: (String, String, String)



-- Извлекает адреса из таблицы отчёта в заданном файле
fromNotes :: String -> Int -> FilePath -> IO [Address]
fromNotes sheet col file = do
   pyFile <- getDataFileName "tables/addresses"
   pyOut  <- pythonStdout $ proc "python" [pyFile, file, sheet, show col]
   return [ Address name name ctx
          | line <- splitOn "\0" pyOut
          , let names = lines line :: [String]
          , col < length names
          , let name  = names !! col
                ctx   = intercalate " | " names
          ]
