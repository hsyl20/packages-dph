
module Util (isPowerOfTwo)
where
	

-- | Check if an integer is a power of two.
isPowerOfTwo :: Int -> Bool
isPowerOfTwo n
	| 0	<- n		= True
	| 2	<- n		= True
	| n `mod` 2 == 0	= isPowerOfTwo (n `div` 2)
	| otherwise		= False



{-
	$ isSorted sorted && (sum elems == sum sorted)

isSorted :: [Int] -> Bool
isSorted xx
 = case xx of
	[]		-> True
	[x]		-> True
	(x1:x2:rest)
	 | x1 <= x2	-> isSorted (x2 : rest)
	 | otherwise	-> False
-}
