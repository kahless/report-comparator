module Main.Body where



import Control.Exception
import Data.List (sortBy)
import Data.Ord (comparing)
import Graphics.UI.Gtk.Builder
import Graphics.UI.Gtk
import Control.Monad
import System.FilePath (replaceBaseName)
import System.Directory (renameFile, removeFile, doesFileExist)

import Utils.Addr
import Utils.GTK
import Utils.Misc (isLeft)
import Data.Types
import Data.Extraction
import Data.Analysis
import Main.Header (obtainPhotos, obtainNotes)



compareReports :: Builder -> IO ()
compareReports b = do
   photos <- obtainPhotos b
   notes  <- obtainNotes b
   case (photos, notes) of
      (Just photos', Just notes') -> draw b photos' notes'
      (_           , _          ) -> return ()



-- Отрисовывает результат сопоставления отчётов
draw :: Builder -> [Parsed] -> [Parsed] -> IO ()
draw b photos notes = do

   let bothMatched      = matched    photos notes
       photosNotParsed  = notParsed  photos
       notesNotParsed   = notParsed  notes
       photosDuplicates = duplicates photos
       notesDuplicates  = duplicates notes
       photosNotMatched = notMatched photos notes
       notesNotMatched  = notMatched notes  photos

   drawNotParsed b "photosNotParsed" photosNotParsed
   drawNotParsed b "notesNotParsed"  notesNotParsed
   --print photosNotParsed
   --print notesNotParsed

   drawDuplicates b "photosDuplicates" photosDuplicates
   drawDuplicates b "notesDuplicates"  notesDuplicates

   drawNotMatched b "photosNotMatched" photosNotMatched
   drawNotMatched b "notesNotMatched"  notesNotMatched
   --print notesNotMatched
   --print photosNotMatched

   drawMatched b bothMatched

   -- Статистика
   drawStat b "photosStat"
            (length photos)
            (length photosDuplicates)
            (length photosNotParsed)
            (length photosNotMatched)
   drawStat b "notesStat"
            (length notes)
            (length notesDuplicates)
            (length notesNotParsed)
            (length notesNotMatched)
   builderGetObject b castToLabel "matchedCount"
      >>= flip labelSetText (show (length bothMatched) ++ " — соответствий")

   when (length bothMatched == 0) $ do
      mainWindow <- builderGetObject b castToWindow "mainWindow"
      alert b "Нет ни одного совпадения адресов.\n\n\
              \Возможно отчёты полностью отличаются \
              \или из них неверно извлечены адреса:\n\n\
              \• Возможно адреса в таблице лежат в другой колонке;\n\n\
              \• Возможно надо воспользоваться переключателем типа файлов, из \
              \которых извлекаются адреса фотоотчёта;"



drawStat :: Builder -> String -> Int -> Int -> Int -> Int -> IO ()
drawStat b containerID total duplicates notParsed notMatched =
   let stat = zip [0..]
            . (:) ( total, "— всего" )
            . filter ( (>0) . fst )
            . sortBy (flip (comparing fst))
            $ [ ( duplicates , "— дубликаты" )
              , ( notParsed  , "— непонятны" )
              , ( notMatched , "— без пары" )
              ]
   in do
      table <- builderGetObject b castToTable containerID
      destroyChildren table
      forM_ stat $ \(i, (num, text)) -> do
         genLabel (show num) >>= addCell table 0 i
         genLabel text       >>= addCell table 1 i
      widgetShowAll table



-- Отрисовывает не распарсенные адреса.
-- Принимает набор данных и id виджета, в который вставлять результат.
drawNotParsed :: Builder -> String -> [Parsed] -> IO ()
drawNotParsed b containerID model = do

   -- Создание таблицы
   table <- tableNew (length model) 3 False -- строк, столбцов, homogeneous
   tableSetRowSpacings table 7
   tableSetColSpacings table 7

   -- Наполнение таблицы строками
   if null model
   then genLabel (italicMeta "Пусто") >>= addCell table 0 0
   else let model' = sortBy ( \ (Parsed (Address x _ _) _)
                                (Parsed (Address y _ _) _)
                              -> x `compare` y
                            ) model
        in forM_ ([0..] `zip` model')
           $ \ (i, parsed@(Parsed (Address string _ _) (Left parseErr))) -> do

              -- Строка адреса
              label <- genLabel string
              set label [ widgetTooltipText := Just (show parseErr)
                        , labelSelectable   := True
                        ]
              miscSetAlignment label 0 0.5
              addCell table 1 i label
              --genLabel "Error not implemented" >>= addCell table 1 i

              -- Кнопка редактирования адреса
              editButton <- buttonNew
              buttonSetImage editButton
                 =<< imageNewFromStock stockEdit (IconSizeUser 1)
              after editButton buttonActivated (editAddress b parsed)
              addCell table 0 i editButton

   -- Таблица помещается в контейнер и показывается результат
   alignment <- builderGetObject b castToAlignment containerID
   destroyChildren alignment
   containerAdd alignment table
   widgetShowAll table



-- Отрисовывает дубликаты адресов.
-- Принимает набор данных и id виджета, в который вставлять результат.
drawDuplicates :: Builder -> String -> [(Parsed, Int)] -> IO ()
drawDuplicates b containerID model = do

   -- Создаю таблицу
   table <- tableNew (length model) 2 False
      -- Количество строк, столбцов, homogeneous
   tableSetRowSpacings table 13
   tableSetColSpacing table 0 7 -- номер колонки, количество пикселей

   -- Наполняю таблицу строками
   if null model
   then genLabel (italicMeta "Пусто") >>= addCell table 0 0
   else let model' = sortBy ( \ ((Parsed (Address x _ _) _), _)
                                ((Parsed (Address y _ _) _), _)
                              -> x `compare` y
                            ) model
        in addLine table `mapM_` zip [0..] model'

   -- Подставляю таблицу в контейнер и показываю результат
   alignment <- builderGetObject b castToAlignment containerID
   destroyChildren alignment
   containerAdd alignment table
   widgetShowAll table

   where

      addLine :: Table -> (Int, (Parsed, Int)) -> IO ()
      addLine table
              ( dupNumber
              ,  ( parsed@(Parsed (Address string _ _) (Right comps))
                 , dupsCount
                 )
              ) = do

         -- Ячейка с текстом адреса
         srcLabel <- genLabel string
         set srcLabel [ widgetTooltipText := Just (format comps)
                      , labelSelectable   := True
                      ]
         miscSetAlignment srcLabel 0 0.5
         addCell table 0 dupNumber srcLabel

         {- Выравнивание слева от адреса по ширине кнопке редактирования
         align <- alignmentNew 0.5 0.5 1 1
         set align [ alignmentLeftPadding := 30 ]
         containerAdd align srcLabel
         addCell table 0 dupNumber align
         -}

         -- Ячейка с количеством дубликатов
         countLabel <- genLabel ("— " ++ show dupsCount ++ " шт.")
         addCell table 1 dupNumber countLabel
         miscSetAlignment countLabel 0 0.5



-- Отрисовывает адреса без пары. Принимает набор данных и идентификатор 
-- виджета, в который вставлять результат.
drawNotMatched :: Builder -> String
               -> [( Parsed
                  ,  Either ErrMsg [(Parsed, Int, Bool)]
                  )]
               -> IO ()
drawNotMatched b containerID model = do

   -- Создаю таблицу для адресов без пар
   table <- tableNew (length model) 2 False -- строк, столбцов, homogeneous
   tableSetRowSpacings table 7
   tableSetColSpacings table 40

   genLabel (meta "Без пары из текущей группы адресов") >>= addCell table 0 0
   genLabel (meta "Похожие из другой группы адресов"  ) >>= addCell table 1 0

   -- Генерю строки с адресами, которым не нашлось пары
   if null model
   then do
      addSeparator table 1
      empty <- genLabel (italicMeta "Пусто")
      miscSetAlignment empty 0 0.5
      addCell table 0 3 empty
   else let model' = sortBy ( \ ((Parsed (Address x _ _) _), _)
                                ((Parsed (Address y _ _) _), _)
                              -> x `compare` y
                            ) model
        in addLine table `mapM_` zip [1..] model'

   -- Подставляю таблицу в контейнер и показываю результат
   alignment <- builderGetObject b castToAlignment containerID
   destroyChildren alignment
   containerAdd alignment table
   widgetShowAll table

   where


      fromLeft (Left x)   = x
      fromRight (Right x) = x


      addLine :: Table
              -> ( Int
                 ,  ( Parsed
                    , Either ErrMsg [(Parsed, Int, Bool)]
                    )
                 )
              -> IO ()
      addLine table
              ( i
              ,  ( parsed@(Parsed (Address string _ _) (Right comps))
                 , options
                 )
              ) = do
         addSeparator table i
         addLeft  table i parsed
         addRight table i options -- похожие адреса


      addSeparator :: Table -> Int -> IO ()
      addSeparator table i = do
         separator <- hSeparatorNew
         tableAttach table separator 0 3 (2*i) (2*i+1) [Fill] [] 0 0


      addLeft :: Table -> Int -> Parsed -> IO ()
      addLeft table i parsed@(Parsed (Address string _ _) (Right comps)) = do

         -- Строка адреса без пары
         leftLabel <- labelNew (Just string)
         miscSetAlignment leftLabel 0 0.5
         set leftLabel
            [ widgetTooltipText := Just (format comps)
            , labelSelectable := True
            ]

         -- Кнопка редактирования адреса
         editButton <- buttonNew
         buttonSetImage editButton
            =<< imageNewFromStock stockEdit (IconSizeUser 1)
         after editButton buttonActivated (editAddress b parsed)

         hbox <- hBoxNew False 7 -- spacing
         containerAdd hbox editButton
         containerAdd hbox leftLabel
         boxSetChildPacking hbox editButton PackNatural 0 PackStart

         -- Чтобы адрес с кнопкой был сверху, а не по центру, они кладутся в 
         -- начало vbox'а. Далее в vbox создаётся ещё один слот для виджета, 
         -- который заполнит пустоту снизу.
         vbox <- vBoxNew False 0 -- spacing
         containerAdd vbox hbox
         containerAdd vbox =<< alignmentNew 0 0 1 1
         boxSetChildPacking vbox hbox PackNatural 0 PackStart
         addCell table 0 (i*2+1) vbox


      addRight :: Table -> Int -> Either ErrMsg [(Parsed, Int, Bool)] -> IO ()
      addRight table i (Left err) = do
         errorLabel <- genLabel (italicMeta err)
         labelSetSelectable errorLabel True
         miscSetAlignment errorLabel 0 0.5
         addCell table 1 (i*2+1) errorLabel
      addRight table i (Right options) = do
         vbox <- vBoxNew True 13 -- homogeneous, spacing
         forM_ options $ \ (parsed, fit, matched) -> do
            -- Создаю одну из альтернатив
            hbox <- hBoxNew False 7
            boxSetHomogeneous hbox False
            alt <- genAltLabel parsed
            miscSetAlignment alt 0 0.5
            boxPackStart hbox alt PackNatural 0
            when matched $ do
                pairedLabel <- genLabel (italicMeta "— уже имеет пару")
                boxPackStart hbox pairedLabel PackNatural 0
            boxPackEndDefaults vbox hbox -- добавляю hbox в конец vbox
         tableAttach table vbox 1 2 (i*2+1) (i*2+2) [Fill] [Fill] 0 6


      genAltLabel :: Parsed -> IO Label
      genAltLabel (Parsed (Address string _ _) comps) = do
         let tooltip = case comps of
                          Left parseErr -> show parseErr
                          Right comps'  -> format comps'
         alt <- genLabel string
         set alt [ widgetTooltipText := Just tooltip
                 , labelSelectable   := True
                 ]
         return alt



drawMatched :: Builder -> [(Parsed, Parsed)] -> IO ()
drawMatched b model = do

   table <- tableNew (length model) 2 False -- строк, столбцов, homogeneous
   tableSetRowSpacings table 7
   tableSetColSpacings table 40

   genLabel (meta "Из фотографий") >>= addCell table 0 0
   genLabel (meta "Из таблицы"  )  >>= addCell table 1 0

   if null model
   then do
      addSeparator table 1
      empty <- genLabel (italicMeta "Пусто")
      miscSetAlignment empty 0 0.5
      addCell table 0 3 empty
   else let model' = sortBy ( \ ((Parsed (Address x _ _) _), _)
                                ((Parsed (Address y _ _) _), _)
                              -> x `compare` y
                            ) model
        in zip [1..] model' `forM_` \ (i, (photo, note)) -> do
           addLine table i photo note

   -- Подставляю таблицу в контейнер и показываю результат
   alignment <- builderGetObject b castToAlignment "matched"
   destroyChildren alignment
   containerAdd alignment table
   widgetShowAll table

   where

      addLine :: Table -> Int -> Parsed -> Parsed -> IO ()
      addLine table i left right = do
         addSeparator table (i*2)
         addCell' table 0 (i*2+1) left
         addCell' table 1 (i*2+1) right

      addSeparator :: Table -> Int -> IO ()
      addSeparator table i = do
         separator <- hSeparatorNew
         tableAttach table separator 0 3 i (i+1) [Fill] [] 0 0

      addCell' :: Table -> Int -> Int -> Parsed -> IO ()
      addCell' table x y (Parsed (Address string _ _) (Right comps)) = do
         label <- labelNew (Just string)
         miscSetAlignment label 0 0.5
         set label
            [ widgetTooltipText := Just (format comps)
            , labelSelectable := True
            ]
         addCell table x y label



editAddress :: Builder -> Parsed -> IO ()
editAddress b (Parsed (Address string origin context) parsed) = do
   -- Создаю диалоговое окно в коде, а не в glade, потому что:
   --
   -- glade не позволяет привязать к кнопкам сигнал response;
   --
   -- gtk2hs не позволяет навесить однократный обработчик сигнала при каждом 
   -- открытии диалога. Это означает, что либо при каждом открытии будут 
   -- навешиваться новые и новые обработчики на этот диалог, либо навешивать 
   -- обработчики диалога вне обработчика клика по кнпоке открытия диалога, 
   -- тогда я не буду иметь доступа к данным вроде Label отчёта;

   let parsed' = case parsed of
                    Right comps -> format comps
                    Left err    -> show err

   -- Dialog
   d <- dialogNew
   set d [ windowTitle := "Редактирование адреса"
         , windowDefaultWidth := 700
         ]
   containerSetBorderWidth d 10

   -- Кнопки
   saveButton <- dialogAddButton d "Сохранить" ResponseAccept
   dialogAddButton d "Отмена" ResponseCancel
   --dialogAddButton d "Удалить" ResponseReject
   dialogSetDefaultResponse d ResponseAccept
   case origin of
      -- TODO: Костыль, пока не реализовано редактирование таблицы
      PhotoOrigin _      -> return ()
      NoteOrigin  _ _ _ _ -> do
         widgetSetSensitive saveButton False
         set saveButton [ widgetTooltipText := Just "Не реализовано" ]

   -- Table
   t <- tableNew 3 2 False -- rows columns homogeneous
   tableSetRowSpacings t 14
   tableSetColSpacings t 14
   containerSetBorderWidth t 5 -- выравниваю содержимое таблицы с кнопками
   flip containerAdd t =<< dialogGetUpper d

   -- Колонка названий
   addressLabel <- labelNew (Just "Адрес:")
   parsedLabel  <- labelNew (Just "Результат разбора:")
   sourceLabel  <- labelNew (Just "Исходник:")
   miscSetAlignment addressLabel 1 0.5 -- xAlign yAlign
   miscSetAlignment parsedLabel  1 0   -- xAlign yAlign
   miscSetAlignment sourceLabel  1 0   -- xAlign yAlign
   tableAttach t addressLabel 0 1 0 1 [Fill] [Expand, Fill] 0 0
   tableAttach t parsedLabel  0 1 1 2 [Fill] [Expand, Fill] 0 0
   tableAttach t sourceLabel  0 1 2 3 [Fill] [Expand, Fill] 0 0

   -- Колонка значений
   addressValue <- entryNew
   parsedValue  <- labelNew (Just parsed')
   sourceValue  <- labelNew (Just context)
   entrySetText addressValue string
   entrySetActivatesDefault addressValue True
   miscSetAlignment parsedValue 0 0 -- xAlign yAlign
   miscSetAlignment sourceValue 0 0 -- xAlign yAlign
   tableAttachDefaults t addressValue 1 2 0 1
   tableAttachDefaults t parsedValue  1 2 1 2
   tableAttachDefaults t sourceValue  1 2 2 3
   labelSetSelectable parsedValue True
   labelSetSelectable sourceValue True
   labelSetLineWrapMode parsedValue WrapPartialWords
   labelSetLineWrapMode sourceValue WrapPartialWords
   labelSetLineWrap parsedValue True
   labelSetLineWrap sourceValue True

   -- События
   on d response $ \ responseID -> case responseID of
      ResponseAccept -> do
         newAddr <- entryGetText addressValue
         when (newAddr /= string)
            $ case origin of
                 NoteOrigin  file sheet col row -> undefined
                 PhotoOrigin file -> do
                    let newFile = replaceBaseName file newAddr
                    exists <- doesFileExist newFile
                    if exists
                    then alert b ("Файл уже существует:\n" ++ newFile)
                    else do
                       renameFile file newFile
                       compareReports b
      -- ResponseReject -> removeFile file
         -- TODO: пока удалить адрес нельзя из соображений безопасности
      _ -> return ()

   widgetShowAll d
   dialogRun d
   widgetDestroy d
