{-# LANGUAGE TypeSynonymInstances, BangPatterns #-}

module Data.Digest.JH (
         jh,
      ) where

import Data.Bits
import Data.Word (Word8, Word64)
import Data.Int (Int64)
import Data.List (foldl')
import Data.Array 
import Data.Binary
import qualified Data.ByteString.Lazy as L 

import Text.Printf (printf)
import Data.BigWord.Word128


type Block512 = (Word128, Word128, Word128, Word128)
type Block1024 = (Block512, Block512)



jh = undefined

-------------------- Conversion between Bytestrings and Word128 -------------

bsToWord128 :: L.ByteString -> Word128
bsToWord128 = decode . L.take 16 



--------------------- testing ------------------

print1024 :: Block1024 -> [String]
print1024 (u,v) = print512 u ++ print512 v

print512 :: Block512 -> [String]
print512 xs = let (a,b,c,d) = tupleMap print128 xs
				  in [a,b,c,d]

print128 :: Word128 -> String
print128 = ("0x" ++) . printf "%032x" . w128toInteger

m0 = ((0,0xaa80000000000000),0,0,0)
m1 = (0,0,0,0x8)
m2 = (0,0,0,0) :: Block512

h0 = ((0,0,0,0),(0,0,0,0)) :: Block1024

kat0 = testF8 ((W 0x8000000000000000 0),0,0,0)
kat1 = testRun ((W 0x4000000000000000 0),0,0,0) (0,0,0,1)
kat2 = testRun ((W 0xe000000000000000 0),0,0,0) (0,0,0,2)

testRun x y = print1024 $ f8 (f8 jh224_H0 x) y 

testRoundFunction = \x n -> (print1024 $ roundFunction x n)

testE8 = print1024 . e8

testF8 = print1024 . f8 jh224_H0

finalize :: Block1024 -> String
finalize (_,(x1,x2,x3,x4)) = 
	printf "0x%056x\n" $ shiftL ((w128toInteger (shiftR x3 32))) 128 + (w128toInteger x4) 


------------------------------------------------


data Parity = Even | Odd
   deriving (Eq, Ord, Read, Show, Ix)

sbox :: Block512 -> Word128 -> Block512
sbox (a0,a1,a2,a3) c = 
   let b3   = complement a3                        --1
       b0   = a0 	`xor` (c .&. (complement a2))    --2
       t    = c   `xor` (b0 .&. a1)             	--3
       b0'  = b0  `xor` (a2 .&. b3)             	--4
       b3'  = b3  `xor` ((complement a1) .&. a2)  	--5
       b1   = a1  `xor` (b0' .&. a2)            	--6
       b2   = a2  `xor` (b0' .&. (complement b3'))	--7
       b0'' = b0' `xor` (b1 .|. b3')            	--8
       b3'' = b3' `xor` (b1 .&. b2)             	--9
       b1'  = b1  `xor` (t .&. b0'')           	 	--10
       b2'  = b2  `xor`t                        	--11
   in (b0'',b1',b2',b3'')

linearTransform :: Block1024 -> Block1024
linearTransform ((a0,a1,a2,a3), (a4,a5,a6,a7)) =
   let b4 = a4 `xor` a1
       b5 = a5 `xor` a2
       b6 = a6 `xor` a3 `xor` a0
       b7 = a7 `xor` a0
       b0 = a0 `xor` b5
       b1 = a1 `xor` b6
       b2 = a2 `xor` b7 `xor` b4
       b3 = a3 `xor` b4
   in ((b0,b1,b2,b3),(b4,b5,b6,b7))

swap :: Int -> Word128 -> Word128
swap 0 = swap1
swap 1 = swap2
swap 2 = swap4
swap 3 = swap8
swap 4 = swap16
swap 5 = swap32
swap 6 = swap64
swap _ = error "Not a number in:  r `mod` 7"

swap1,swap2,swap4,swap8,swap16,swap32,swap64 :: Word128 -> Word128

swap1 x = shiftL (x .&. 0x55555555555555555555555555555555) 1 
          .|. 
          shiftR (x .&. 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa) 1 

swap2 x = shiftL (x .&. 0x33333333333333333333333333333333) 2 
          .|. 
          shiftR (x .&. 0xcccccccccccccccccccccccccccccccc) 2           

swap4 x = shiftL (x .&. 0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f) 4 
          .|. 
          shiftR (x .&. 0xf0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0) 4           

swap8 x = shiftL (x .&. 0x00ff00ff00ff00ff00ff00ff00ff00ff) 8 
          .|. 
          shiftR (x .&. 0xff00ff00ff00ff00ff00ff00ff00ff00) 8            

swap16 x = shiftL (x .&. 0x0000ffff0000ffff0000ffff0000ffff) 16 
           .|. 
           shiftR (x .&. 0xffff0000ffff0000ffff0000ffff0000) 16           

swap32 x = shiftL (x .&. 0x00000000ffffffff00000000ffffffff) 32 
           .|. 
           shiftR (x .&. 0xffffffff00000000ffffffff00000000) 32 

swap64 (W hi lo) = W lo hi

roundFunction :: Block1024 -> Int -> Block1024
roundFunction ((a0,a1,a2,a3),(a4,a5,a6,a7)) roundNr = 
   let r = roundNr `mod` 7
       evens = sbox (a0, a2, a4, a6) (constants ! (roundNr, Even))
       odds  = sbox (a1, a3, a5, a7) (constants ! (roundNr, Odd))
       ((b0,b2,b4,b6),oddsTransformed) = linearTransform (evens,odds)
       (b1,b3,b5,b7) = tupleMap (swap r) oddsTransformed
   in ((b0,b1,b2,b3),(b4,b5,b6,b7))
 
e8 :: Block1024 -> Block1024
e8 hs = foldl' roundFunction hs [0..41] 

f8 :: Block1024 -> Block512 -> Block1024
f8 (hh, hl) m = let ah =  tupleZip xor hh m
                    (bh, bl) = e8 (ah, hl)
                in (bh, tupleZip xor bl m)

---------------------- Utility functions -----------------

tupleZip :: (a -> b -> c) -> (a, a, a, a) -> (b, b, b, b) -> (c, c, c, c)
tupleZip f (a1,a2,a3,a4) (b1,b2,b3,b4) = (f a1 b1, f a2 b2, f a3 b3, f a4 b4) 

tupleMap :: (a -> b) -> (a, a, a, a) -> (b, b, b, b)
tupleMap f (a0,a1,a2,a3) = (f a0, f a1, f a2, f a3)

-------------- Constants -------------------

-- Initial hash values
jh224_H0 =
	((0x2dfedd62f99a98acae7cacd619d634e7,0xa4831005bc301216b86038c6c9661494,
	  0x66d9899f2580706fce9ea31b1d9b1adc,0x11e8325f7b366e10f994857f02fa06c1),
	  
	 (0x1b4f1b5cd8c840b397f6a17f6e738099,0xdcdf93a5adeaa3d3a431e8dec9539a68,
	  0x22b4a98aec86a1e4d574ac959ce56cf0,0x15960deab5ab2bbf9611dcf0dd64ea6e))



-- Round constants
constants :: Array (Int,Parity) Word128
constants = array ((0, Even), (41, Odd)) $ zip [(i,p) | i <- [0..41], p <- [Even,Odd]]
     [0x72d5dea2df15f8677b84150ab7231557, 0x81abd6904d5a87f64e9f4fc5c3d12b40,
		0xea983ae05c45fa9c03c5d29966b2999a, 0x660296b4f2bb538ab556141a88dba231,
		0x03a35a5c9a190edb403fb20a87c14410, 0x1c051980849e951d6f33ebad5ee7cddc,
		0x10ba139202bf6b41dc786515f7bb27d0, 0x0a2c813937aa78503f1abfd2410091d3,
		0x422d5a0df6cc7e90dd629f9c92c097ce, 0x185ca70bc72b44acd1df65d663c6fc23,
		0x976e6c039ee0b81a2105457e446ceca8, 0xeef103bb5d8e61fafd9697b294838197,
		0x4a8e8537db03302f2a678d2dfb9f6a95, 0x8afe7381f8b8696c8ac77246c07f4214,
		0xc5f4158fbdc75ec475446fa78f11bb80, 0x52de75b7aee488bc82b8001e98a6a3f4,
		0x8ef48f33a9a36315aa5f5624d5b7f989, 0xb6f1ed207c5ae0fd36cae95a06422c36,
		0xce2935434efe983d533af974739a4ba7, 0xd0f51f596f4e81860e9dad81afd85a9f,
		0xa7050667ee34626a8b0b28be6eb91727, 0x47740726c680103fe0a07e6fc67e487b,
		0x0d550aa54af8a4c091e3e79f978ef19e, 0x8676728150608dd47e9e5a41f3e5b062,
		0xfc9f1fec4054207ae3e41a00cef4c984, 0x4fd794f59dfa95d8552e7e1124c354a5,
		0x5bdf7228bdfe6e2878f57fe20fa5c4b2, 0x05897cefee49d32e447e9385eb28597f,
		0x705f6937b324314a5e8628f11dd6e465, 0xc71b770451b920e774fe43e823d4878a,
		0x7d29e8a3927694f2ddcb7a099b30d9c1, 0x1d1b30fb5bdc1be0da24494ff29c82bf,
		0xa4e7ba31b470bfff0d324405def8bc48, 0x3baefc3253bbd339459fc3c1e0298ba0,
		0xe5c905fdf7ae090f947034124290f134, 0xa271b701e344ed95e93b8e364f2f984a,
		0x88401d63a06cf61547c1444b8752afff, 0x7ebb4af1e20ac6304670b6c5cc6e8ce6,
		0xa4d5a456bd4fca00da9d844bc83e18ae, 0x7357ce453064d1ade8a6ce68145c2567,
		0xa3da8cf2cb0ee11633e906589a94999a, 0x1f60b220c26f847bd1ceac7fa0d18518,
		0x32595ba18ddd19d3509a1cc0aaa5b446, 0x9f3d6367e4046bbaf6ca19ab0b56ee7e,
		0x1fb179eaa9282174e9bdf7353b3651ee, 0x1d57ac5a7550d3763a46c2fea37d7001,
		0xf735c1af98a4d84278edec209e6b6779, 0x41836315ea3adba8fac33b4d32832c83,
		0xa7403b1f1c2747f35940f034b72d769a, 0xe73e4e6cd2214ffdb8fd8d39dc5759ef,
		0x8d9b0c492b49ebda5ba2d74968f3700d, 0x7d3baed07a8d5584f5a5e9f0e4f88e65,
		0xa0b8a2f436103b530ca8079e753eec5a, 0x9168949256e8884f5bb05c55f8babc4c,
		0xe3bb3b99f387947b75daf4d6726b1c5d, 0x64aeac28dc34b36d6c34a550b828db71,
		0xf861e2f2108d512ae3db643359dd75fc, 0x1cacbcf143ce3fa267bbd13c02e843b0,
		0x330a5bca8829a1757f34194db416535c, 0x923b94c30e794d1e797475d7b6eeaf3f,
		0xeaa8d4f7be1a39215cf47e094c232751, 0x26a32453ba323cd244a3174a6da6d5ad,
		0xb51d3ea6aff2c90883593d98916b3c56, 0x4cf87ca17286604d46e23ecc086ec7f6,
		0x2f9833b3b1bc765e2bd666a5efc4e62a, 0x06f4b6e8bec1d43674ee8215bcef2163,
		0xfdc14e0df453c969a77d5ac406585826, 0x7ec1141606e0fa167e90af3d28639d3f,
		0xd2c9f2e3009bd20c5faace30b7d40c30, 0x742a5116f2e032980deb30d8e3cef89a,
		0x4bc59e7bb5f17992ff51e66e048668d3, 0x9b234d57e6966731cce6a6f3170a7505,
		0xb17681d913326cce3c175284f805a262, 0xf42bcbb378471547ff46548223936a48,
		0x38df58074e5e6565f2fc7c89fc86508e, 0x31702e44d00bca86f04009a23078474e,
		0x65a0ee39d1f73883f75ee937e42c3abd, 0x2197b2260113f86fa344edd1ef9fdee7,
		0x8ba0df15762592d93c85f7f612dc42be, 0xd8a7ec7cab27b07e538d7ddaaa3ea8de,
		0xaa25ce93bd0269d85af643fd1a7308f9, 0xc05fefda174a19a5974d66334cfd216a,
		0x35b49831db411570ea1e0fbbedcd549b, 0x9ad063a151974072f6759dbf91476fe2]
