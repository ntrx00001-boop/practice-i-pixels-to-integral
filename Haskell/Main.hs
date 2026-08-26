{- |
Practice I — From pixels to the integral (Haskell)

Pipeline made explicit:

  PBM P4 file → bytes → pixels → f(x) → M → area = sum M

f(x) is the number of consecutive black pixels counted from the bottom of
column x until the first white pixel.  With Δx = 1, the Riemann sum is
exactly the sum of the heights.
-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import           Data.Bits            (testBit)
import qualified Data.ByteString      as B
import           Data.Char            (chr, isDigit, isSpace)
import           Data.Word            (Word8)
import           System.Environment   (getArgs)
import           System.IO            (hSetEncoding, stdout, utf8)
import           Text.Printf          (printf)

-- | Packed binary PBM (magic P4).
data PBM = PBM
  { width       :: Int
  , height      :: Int
  , bytesPerRow :: Int
  , raster      :: B.ByteString
  } deriving (Show)

main :: IO ()
main = do
  hSetEncoding stdout utf8
  args <- getArgs
  let path = case args of
        (p:_) -> p
        []    -> "curva_binaria_P4.pbm"
  raw <- B.readFile path
  case parseP4 raw of
    Left err  -> putStrLn ("Error: " ++ err)
    Right pbm -> run pbm path

run :: PBM -> FilePath -> IO ()
run pbm path = do
  let m     = heights pbm          -- M = map f [0 .. width-1]
      area  = sum m                -- A = Σ f(x_i) Δx, Δx = 1
      n     = width pbm
      samples = samplePositions n 10
  putStrLn "============================================================"
  putStrLn "  Practice I — Haskell (functional)"
  putStrLn "============================================================"
  putStrLn $ "File          : " ++ path
  putStrLn $ "Dimensions    : " ++ show n ++ " x " ++ show (height pbm)
  putStrLn $ "Domain        : x = 0 .. " ++ show (n - 1)
  putStrLn $ "Area (pixels²): " ++ show area
  putStrLn ""
  putStrLn "-- Console view of the source curve (downsampled) --"
  putStrLn $ "Strategy: each glyph is a block of "
           ++ show (blockW n) ++ "×" ++ show (blockH (height pbm))
           ++ " pixels; a cell is black if a majority of sampled pixels are black."
  putStrLn ""
  putStr $ renderImage pbm
  putStrLn ""
  putStrLn "-- Height function M[x] = f(x) (downsampled bars) --"
  putStrLn ""
  putStr $ renderHeights m
  putStrLn ""
  putStrLn "-- Sample values x_i → f(x_i) --"
  mapM_ (printSample m) (zip [0 :: Int ..] samples)
  putStrLn ""
  putStrLn $ "Check: length M = " ++ show (length m)
          ++ "  |  sum M = " ++ show area

printSample :: [Int] -> (Int, Int) -> IO ()
printSample m (i, x) =
  printf "x_%d = %d -> f(x_%d) = %d pixels\n" i x i (m !! x)

-- ------------------------------------------------------------------
-- Functional core: domain → f → M → area
-- ------------------------------------------------------------------

-- | Height of column x: consecutive black pixels from the bottom.
--   Stops at the first white pixel (or the top of the image).
f :: PBM -> Int -> Int
f pbm x = go (height pbm - 1) 0
  where
    go y acc
      | y < 0          = acc
      | pixel pbm x y  = go (y - 1) (acc + 1)  -- y = 0 is the top row
      | otherwise      = acc

-- | M = map f [0 .. width - 1]
heights :: PBM -> [Int]
heights pbm = map (f pbm) [0 .. width pbm - 1]

-- | Pixel (x, y) is black (PBM: 1 = black).  y = 0 is the top of the image.
pixel :: PBM -> Int -> Int -> Bool
pixel pbm x y
  | x < 0 || x >= width pbm || y < 0 || y >= height pbm = False
  | otherwise =
      let byteIx = y * bytesPerRow pbm + x `div` 8
          bitIx  = 7 - (x `mod` 8)          -- P4: most significant bit first
          byte   = raster pbm `B.index` byteIx
      in  testBit byte bitIx

-- ------------------------------------------------------------------
-- PBM P4 parser (binary, 8 pixels per byte, MSB = leftmost pixel)
-- ------------------------------------------------------------------

parseP4 :: B.ByteString -> Either String PBM
parseP4 bs = do
  rest1 <- expectMagic bs
  (w, rest2) <- readInt rest1
  (h, rest3) <- readInt rest2
  rasterBytes <- skipOneWhitespace rest3
  let bpr = (w + 7) `div` 8
      expected = bpr * h
  if B.length rasterBytes < expected
    then Left $ "Raster too short: got " ++ show (B.length rasterBytes)
              ++ ", expected " ++ show expected
    else Right PBM
      { width       = w
      , height      = h
      , bytesPerRow = bpr
      , raster      = B.take expected rasterBytes
      }

expectMagic :: B.ByteString -> Either String B.ByteString
expectMagic bs
  | B.length bs < 2          = Left "File too short"
  | B.take 2 bs /= "P4"      = Left "Not a PBM P4 file (magic is not P4)"
  | otherwise                = Right (skipWsAndComments (B.drop 2 bs))

skipWsAndComments :: B.ByteString -> B.ByteString
skipWsAndComments bs
  | B.null bs = bs
  | B.head bs == hash = skipWsAndComments (dropLine (B.tail bs))
  | isSpace (chr8 (B.head bs)) = skipWsAndComments (B.tail bs)
  | otherwise = bs
  where
    hash = 35 -- '#'

dropLine :: B.ByteString -> B.ByteString
dropLine bs = case B.elemIndex 10 bs of
  Just i  -> B.drop (i + 1) bs
  Nothing -> B.empty

readInt :: B.ByteString -> Either String (Int, B.ByteString)
readInt bs =
  let bs' = skipWsAndComments bs
      (digits, rest) = B.span (isDigit . chr8) bs'
  in if B.null digits
       then Left "Expected an integer in the PBM header"
       else Right (read (map chr8 (B.unpack digits)), rest)

skipOneWhitespace :: B.ByteString -> Either String B.ByteString
skipOneWhitespace bs
  | B.null bs = Left "Missing whitespace before raster"
  | isSpace (chr8 (B.head bs)) = Right (B.tail bs)
  | B.head bs == 35 = skipOneWhitespace (skipWsAndComments bs)
  | otherwise = Right bs

chr8 :: Word8 -> Char
chr8 = chr . fromIntegral

-- ------------------------------------------------------------------
-- Console visualisation (spatial sampling / block aggregation)
-- ------------------------------------------------------------------

targetCols, targetRows, barRows :: Int
targetCols = 72
targetRows = 22
barRows    = 16

blockW :: Int -> Int
blockW n = max 1 (n `div` targetCols)

blockH :: Int -> Int
blockH h = max 1 (h `div` targetRows)

-- | Downsampled bitmap of the filled region under the curve.
renderImage :: PBM -> String
renderImage pbm =
  unlines [ [cell x0 y0 | x0 <- [0, bw .. width pbm - 1]]
          | y0 <- [0, bh .. height pbm - 1]
          ]
  where
    bw = blockW (width pbm)
    bh = blockH (height pbm)
    cell x0 y0 =
      let blacks =
            [ 1 | dy <- [0 .. min 3 (bh - 1)]
                , dx <- [0 .. min 3 (bw - 1)]
                , pixel pbm (x0 + dx) (y0 + dy)
                ]
          total = (min 4 bh) * (min 4 bw)
      in if 2 * sum blacks >= total then '█' else ' '

-- | Bar chart of M, sampled horizontally to fit the console.
renderHeights :: [Int] -> String
renderHeights m
  | null m    = "(empty M)\n"
  | otherwise =
      unlines (axis : bars ++ [baseline, labels])
  where
    step   = max 1 (length m `div` targetCols)
    sampled = [ m !! i | i <- [0, step .. length m - 1] ]
    peak   = maximum (1 : sampled)
    bars =
      [ [ if h * barRows >= row * peak then '█' else ' '
        | h <- sampled
        ]
      | row <- [barRows, barRows - 1 .. 1]
      ]
    baseline = replicate (length sampled) '─'
    axis     = "f(x) ↑  (scaled to max height " ++ show peak ++ ")"
    labels   = "x →  0" ++ replicate (max 0 (length sampled - 12)) ' '
            ++ show (length m - 1)

samplePositions :: Int -> Int -> [Int]
samplePositions n k
  | n <= 0    = []
  | k <= 1    = [0]
  | otherwise = [ min (n - 1) ((i * (n - 1)) `div` (k - 1)) | i <- [0 .. k - 1] ]
