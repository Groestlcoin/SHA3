{-# LANGUAGE BangPatterns #-}

module Data.Digest.Groestl where

import Data.Word (Word64, Word8)
import Data.Int (Int64) 	
import Data.Bits (xor, (.&.), shiftR, setBit)
import Data.List (foldl')
import qualified Data.Binary as B
import qualified Data.Binary.Get as G
import qualified Data.ByteString.Lazy as L
import qualified Data.Vector.Unboxed as V
import qualified Data.Vector.Unboxed.Mutable as MV
import qualified Data.Vector.Generic as G
import Control.Exception.Base (assert)
import Text.Printf
import Control.Monad
import Control.Monad.Primitive (PrimMonad, PrimState)
import Prelude hiding (truncate)
import Control.Parallel (par, pseq)

import Data.Digest.GroestlTables

printWAsHex :: Word64 -> String
printWAsHex = printf "0x%016x"

readAsHex :: String -> L.ByteString
readAsHex = L.pack . map (read . ("0x"++)) . take2

take2 :: [a] -> [[a]]
take2 (a:b:rest) = [a,b] : take2 rest
take2 _          = []

printAsHex :: L.ByteString -> String
printAsHex = concat . ("0x" :) . map (printf "%02x") . L.unpack

--------------------------------------------------------------------------------

data DigestLength = G224 | G256 | G384 | G512

-----------------------------------------------------------------------------------

groestl224 :: Int64 -> L.ByteString -> L.ByteString
groestl224 dataBitLen 
    | dataBitLen < 0 = error "The data length can not be less than 0"
    | otherwise = truncate G224 . outputTransformation . foldl' f512 h0_224 . parseMessage dataBitLen 512

outputTransformation :: V.Vector Word64 -> V.Vector Word64
outputTransformation x = V.zipWith xor (permP x) x 

f512 :: V.Vector Word64 -> V.Vector Word64 -> V.Vector Word64
f512 h m = V.force outP `par` (V.force outQ `pseq` (V.zipWith3 xor3 h outP outQ))
    where xor3 x1 x2 x3 = x1 `xor` x2 `xor` x3
          inP = V.zipWith xor h m
          outP = permP inP
          outQ = permQ m
    
column :: V.Vector Word64
       -> Int -> Int -> Int -> Int
       -> Int -> Int -> Int -> Int 
       -> Word64
column v c0 c1 c2 c3 c4 c5 c6 c7 = 
    V.unsafeIndex tables (index 0 c0) `xor`
    V.unsafeIndex tables (index 1 c1) `xor`
    V.unsafeIndex tables (index 2 c2) `xor`
    V.unsafeIndex tables (index 3 c3) `xor`
    V.unsafeIndex tables (index 4 c4) `xor`
    V.unsafeIndex tables (index 5 c5) `xor`
    V.unsafeIndex tables (index 6 c6) `xor`
    V.unsafeIndex tables (index 7 c7) 
    
    where index i c = i * 256 + fromIntegral (extractByte i (v V.! c))

extractByte :: Int -> Word64 -> Word8
extractByte n w = fromIntegral $ shiftR w (8 * (7 - n))

permQ :: V.Vector Word64 -> V.Vector Word64
permQ x = V.foldl' rnd512Q x (V.enumFromN 0 10) 

rnd512Q :: V.Vector Word64 -> Word64 -> V.Vector Word64
rnd512Q !x !rndNr = 
    let !x0 = V.unsafeIndex x 0 `xor` 0xffffffffffffffff `xor` rndNr
        !x1 = V.unsafeIndex x 1 `xor` 0xffffffffffffffef `xor` rndNr
        !x2 = V.unsafeIndex x 2 `xor` 0xffffffffffffffdf `xor` rndNr
        !x3 = V.unsafeIndex x 3 `xor` 0xffffffffffffffcf `xor` rndNr
        !x4 = V.unsafeIndex x 4 `xor` 0xffffffffffffffbf `xor` rndNr
        !x5 = V.unsafeIndex x 5 `xor` 0xffffffffffffffaf `xor` rndNr
        !x6 = V.unsafeIndex x 6 `xor` 0xffffffffffffff9f `xor` rndNr
        !x7 = V.unsafeIndex x 7 `xor` 0xffffffffffffff8f `xor` rndNr
        !y  = V.fromList [x0, x1, x2, x3, x4, x5, x6, x7]
      
        !w0 = column y 1 3 5 7 0 2 4 6
        !w1 = column y 2 4 6 0 1 3 5 7
        !w2 = column y 3 5 7 1 2 4 6 0
        !w3 = column y 4 6 0 2 3 5 7 1
        !w4 = column y 5 7 1 3 4 6 0 2
        !w5 = column y 6 0 2 4 5 7 1 3
        !w6 = column y 7 1 3 5 6 0 2 4
        !w7 = column y 0 2 4 6 7 1 3 5
    in V.fromList [w0, w1, w2, w3, w4, w5, w6, w7]

permP :: V.Vector Word64 -> V.Vector Word64
permP x = V.foldl' rnd512P x (V.enumFromStepN 0 0x0100000000000000 10) 

rnd512P :: V.Vector Word64 -> Word64 -> V.Vector Word64
rnd512P !x rndNr = 
    let !x0 = V.unsafeIndex x 0 `xor` 0x0000000000000000 `xor` rndNr
        !x1 = V.unsafeIndex x 1 `xor` 0x1000000000000000 `xor` rndNr
        !x2 = V.unsafeIndex x 2 `xor` 0x2000000000000000 `xor` rndNr
        !x3 = V.unsafeIndex x 3 `xor` 0x3000000000000000 `xor` rndNr
        !x4 = V.unsafeIndex x 4 `xor` 0x4000000000000000 `xor` rndNr
        !x5 = V.unsafeIndex x 5 `xor` 0x5000000000000000 `xor` rndNr
        !x6 = V.unsafeIndex x 6 `xor` 0x6000000000000000 `xor` rndNr
        !x7 = V.unsafeIndex x 7 `xor` 0x7000000000000000 `xor` rndNr
        !y  = V.fromList [x0, x1, x2, x3, x4, x5, x6, x7]
      
        !w0 = column y 0 1 2 3 4 5 6 7
        !w1 = column y 1 2 3 4 5 6 7 0
        !w2 = column y 2 3 4 5 6 7 0 1
        !w3 = column y 3 4 5 6 7 0 1 2 
        !w4 = column y 4 5 6 7 0 1 2 3
        !w5 = column y 5 6 7 0 1 2 3 4
        !w6 = column y 6 7 0 1 2 3 4 5
        !w7 = column y 7 0 1 2 3 4 5 6
    in V.fromList [w0, w1, w2, w3, w4, w5, w6, w7]


---------------------------- Parsing ------------------------------
parseMessage :: Int64 -> Int64 -> L.ByteString -> [V.Vector Word64]
parseMessage dataLen blockLen xs
   | L.null suf   = pad dataLen blockLen pre
   | otherwise    = parseBlock pre : parseMessage dataLen blockLen suf
   where (!pre,suf) = L.splitAt 64 xs


parseBlock :: L.ByteString  -> V.Vector Word64
parseBlock = V.unfoldr (\bs -> if L.null bs then Nothing else Just (G.runGet G.getWord64be bs, L.drop 8 bs))

pad :: Int64 -> Int64 -> L.ByteString -> [V.Vector Word64]
pad dataLen blockLen xs
    | dataLen == 0 || L.null xs = [V.fromList [0x8000000000000000, 0,0,0,0,0,0, lengthPad + 1]] 
    | partialBlockLen == 0 = [parseBlock xs, V.fromList [0x8000000000000000, 0,0,0,0,0,0, lengthPad + 1]]  
    | L.length onePadded <= (blockByteLen - 8) = [V.unsafeUpdate (parseBlock fullBlock) (V.singleton (7, lengthPad + 1))]
    | otherwise = [parseBlock fullBlock, V.fromList [0,0,0,0,0,0,0, lengthPad + 2]]
    where w = (blockLen - (8 * L.length xs) - 65) `mod` blockLen
          onePadded = appendOne xs partialBlockLen
          fullBlock = L.append onePadded (L.take (blockByteLen - L.length onePadded) zeroes) 
          zeroes = L.repeat 0x00
          blockByteLen = blockLen `div` 8
          partialBlockLen = dataLen `rem` blockLen
          lengthPad = fromIntegral $ dataLen `div` blockLen

appendOne :: L.ByteString -> Int64 -> L.ByteString
appendOne xs len
    | len == 0 || L.null xs = L.singleton 0x80
    | byteOffset == 0 =  L.snoc xs 0x80
    | otherwise = L.snoc (L.init xs) (setBit (L.last xs) (7 - byteOffset))
    where byteOffset = fromIntegral $ len `mod` 8

truncate :: DigestLength -> V.Vector Word64 -> L.ByteString
truncate G224 = L.drop 4 . L.concat . map B.encode . V.toList . V.unsafeSlice 4 4 
----------------------------------------------------------------------------------

h0_224 :: V.Vector Word64
h0_224 = V.fromList [0, 0, 0, 0, 0, 0, 0, 0xe0]

