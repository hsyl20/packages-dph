{-# LANGUAGE CPP #-}

#include "fusion-phases.h"

module Data.Array.Parallel.Lifted.Combinators (
  lengthPA, replicatePA, singletonPA, mapPA, crossMapPA,
  zipWithPA, zipPA, unzipPA, 
  packPA, filterPA, combine2PA, indexPA, concatPA, appPA, enumFromToPA_Int,

  lengthPA_v, replicatePA_v, singletonPA_v, zipPA_v, unzipPA_v,
  indexPA_v, appPA_v, enumFromToPA_v
) where

import Data.Array.Parallel.Lifted.PArray
import Data.Array.Parallel.Lifted.Closure
import Data.Array.Parallel.Lifted.Unboxed
import Data.Array.Parallel.Lifted.Repr
import Data.Array.Parallel.Lifted.Instances

import GHC.Exts (Int(..), (+#), (-#), Int#, (<#))

lengthPA_v :: PA a -> PArray a -> Int
{-# INLINE_PA lengthPA_v #-}
lengthPA_v pa xs = I# (lengthPA# pa xs)

lengthPA_l :: PA a -> PArray (PArray a) -> PArray Int
{-# INLINE_PA lengthPA_l #-}
lengthPA_l pa (PNested n# lens _ _) = PInt n# lens

lengthPA :: PA a -> (PArray a :-> Int)
{-# INLINE lengthPA #-}
lengthPA pa = closure1 (lengthPA_v pa) (lengthPA_l pa)

replicatePA_v :: PA a -> Int -> a -> PArray a
{-# INLINE_PA replicatePA_v #-}
replicatePA_v pa (I# n#) x = replicatePA# pa n# x

replicatePA_l :: PA a -> PArray Int -> PArray a -> PArray (PArray a)
{-# INLINE_PA replicatePA_l #-}
replicatePA_l pa (PInt n# ns) xs
  = PNested n# ns (indicesSegdPA# segd)
                  (replicatelPA# pa segd xs)
  where
    segd = lengthsToSegdPA# ns

replicatePA :: PA a -> (Int :-> a :-> PArray a)
{-# INLINE replicatePA #-}
replicatePA pa = closure2 dPA_Int (replicatePA_v pa) (replicatePA_l pa)

singletonPA_v :: PA a -> a -> PArray a
{-# INLINE_PA singletonPA_v #-}
singletonPA_v pa x = replicatePA_v pa 1 x

singletonPA_l :: PA a -> PArray a -> PArray (PArray a)
{-# INLINE_PA singletonPA_l #-}
singletonPA_l pa xs
  = case lengthPA# pa xs of
      n# -> PNested n# (replicatePA_Int# n# 1#) (upToPA_Int# n#) xs

singletonPA :: PA a -> (a :-> PArray a)
{-# INLINE singletonPA #-}
singletonPA pa = closure1 (singletonPA_v pa) (singletonPA_l pa)

mapPA_v :: PA a -> PA b -> (a :-> b) -> PArray a -> PArray b
{-# INLINE_PA mapPA_v #-}
mapPA_v pa pb f as = replicatePA# (dPA_Clo pa pb) (lengthPA# pa as) f
                     $:^ as

mapPA_l :: PA a -> PA b
        -> PArray (a :-> b) -> PArray (PArray a) -> PArray (PArray b)
{-# INLINE_PA mapPA_l #-}
mapPA_l pa pb fs xss@(PNested n# lens idxs xs)
  = PNested n# lens idxs
            (replicatelPA# (dPA_Clo pa pb) (segdOfPA# pa xss) fs $:^ xs)

mapPA :: PA a -> PA b -> ((a :-> b) :-> PArray a :-> PArray b)
{-# INLINE mapPA #-}
mapPA pa pb = closure2 (dPA_Clo pa pb) (mapPA_v pa pb) (mapPA_l pa pb)

crossMapPA_v :: PA a -> PA b -> PArray a -> (a :-> PArray b) -> PArray (a,b)
{-# INLINE_PA crossMapPA_v #-}
crossMapPA_v pa pb as f
  = zipPA# pa pb (replicatelPA# pa (segdOfPA# pb bss) as) (concatPA# bss)
  where
    bss = mapPA_v pa (dPA_PArray pb) f as

crossMapPA_l :: PA a -> PA b
             -> PArray (PArray a)
             -> PArray (a :-> PArray b)
             -> PArray (PArray (a,b))
{-# INLINE_PA crossMapPA_l #-}
crossMapPA_l pa pb ass@(PNested _ _ _ as) fs
  = case concatPA_l pb bsss of
      PNested n# lens1 idxs1 bs -> PNested n# lens1 idxs1 (zipPA# pa pb as' bs)
  where
    bsss@(PNested _ _ _ bss)
      = mapPA_l pa (dPA_PArray pb) fs ass

    as' = replicatelPA# pa (segdOfPA# pb bss) as

crossMapPA :: PA a -> PA b -> (PArray a :-> (a :-> PArray b) :-> PArray (a,b))
{-# INLINE crossMapPA #-}
crossMapPA pa pb = closure2 (dPA_PArray pa) (crossMapPA_v pa pb)
                                            (crossMapPA_l pa pb)

zipPA_v :: PA a -> PA b -> PArray a -> PArray b -> PArray (a,b)
{-# INLINE_PA zipPA_v #-}
zipPA_v pa pb xs ys = zipPA# pa pb xs ys

zipPA_l :: PA a -> PA b
        -> PArray (PArray a) -> PArray (PArray b) -> PArray (PArray (a,b))
{-# INLINE_PA zipPA_l #-}
zipPA_l pa pb (PNested n# lens idxs xs) (PNested _ _ _ ys)
  = PNested n# lens idxs (zipPA_v pa pb xs ys)

zipPA :: PA a -> PA b -> (PArray a :-> PArray b :-> PArray (a,b))
{-# INLINE zipPA #-}
zipPA pa pb = closure2 (dPA_PArray pa) (zipPA_v pa pb) (zipPA_l pa pb)

zipWithPA_v :: PA a -> PA b -> PA c
            -> (a :-> b :-> c) -> PArray a -> PArray b -> PArray c
{-# INLINE_PA zipWithPA_v #-}
zipWithPA_v pa pb pc f as bs = replicatePA# (dPA_Clo pa (dPA_Clo pb pc))
                                            (lengthPA# pa as)
                                            f
                                $:^ as $:^ bs

zipWithPA_l :: PA a -> PA b -> PA c
            -> PArray (a :-> b :-> c) -> PArray (PArray a) -> PArray (PArray b)
            -> PArray (PArray c)
{-# INLINE_PA zipWithPA_l #-}
zipWithPA_l pa pb pc fs ass@(PNested n# lens idxs as) (PNested _ _ _ bs)
  = PNested n# lens idxs
            (replicatelPA# (dPA_Clo pa (dPA_Clo pb pc))
                           (segdOfPA# pa ass) fs $:^ as $:^ bs)

zipWithPA :: PA a -> PA b -> PA c
          -> ((a :-> b :-> c) :-> PArray a :-> PArray b :-> PArray c)
{-# INLINE zipWithPA #-}
zipWithPA pa pb pc = closure3 (dPA_Clo pa (dPA_Clo pb pc)) (dPA_PArray pa)
                              (zipWithPA_v pa pb pc)
                              (zipWithPA_l pa pb pc)

unzipPA_v:: PA a -> PA b -> PArray (a,b) -> (PArray a, PArray b)
unzipPA_v pa pb abs =  unzipPA# pa pb abs

unzipPA_l:: PA a -> PA b -> PArray (PArray (a, b)) -> PArray ((PArray a), (PArray b))
unzipPA_l pa pb (PNested n lens idxys xys) = 
  P_2 n  (PNested n lens idxys xs) (PNested n lens idxys ys)
  where
    (xs, ys) = unzipPA_v pa pb xys     

unzipPA:: PA a -> PA b -> (PArray (a, b) :-> (PArray a, PArray b))  
{-# INLINE unzipPA #-}
unzipPA pa pb =  closure1 (unzipPA_v pa pb) (unzipPA_l pa pb)

packPA_v :: PA a -> PArray a -> PArray Bool -> PArray a
{-# INLINE_PA packPA_v #-}
packPA_v pa xs bs = packPA# pa xs (truesPA# bs) (toPrimArrPA_Bool bs)

packPA_l :: PA a
         -> PArray (PArray a) -> PArray (PArray Bool) -> PArray (PArray a)
{-# INLINE_PA packPA_l #-}
packPA_l pa (PNested _ _ _ xs) bss
  = PNested (lengthPA# (dPA_PArray dPA_Bool) bss) lens' idxs' (packPA_v pa xs bs)
  where
    lens' = truesPAs_Bool# segd (toPrimArrPA_Bool bs)
    idxs' = unsafe_scanPA_Int# (+) 0 lens'
    segd  = segdOfPA# dPA_Bool bss
    bs    = concatPA# bss

packPA :: PA a -> (PArray a :-> PArray Bool :-> PArray a)
{-# INLINE packPA #-}
packPA pa = closure2 (dPA_PArray pa) (packPA_v pa) (packPA_l pa)


-- TODO: should the selector be a boolean array?
--       fix index vector
combine2PA_v:: PA a -> PArray a -> PArray a -> PArray Int -> PArray a
{-# INLINE_PA combine2PA_v #-}
combine2PA_v pa xs ys bs@(PInt _ bs#) = 
  combine2PA# pa (lengthPA# pa xs +# lengthPA# pa ys) bs# bs# xs ys

combine2PA_l:: PA a -> PArray (PArray a) -> PArray (PArray a) -> PArray (PArray Int) -> PArray (PArray a)
{-# INLINE_PA combine2PA_l #-}
combine2PA_l _ _ _ _ = error "combinePA_l nyi"
    

combine2PA:: PA a -> (PArray a :-> PArray a :-> PArray Int :-> PArray a)
{-# INLINE_PA combine2PA #-}
combine2PA pa = closure3 (dPA_PArray pa) (dPA_PArray pa) (combine2PA_v pa) (combine2PA_l pa)


filterPA_v :: PA a -> (a :-> Bool) -> PArray a -> PArray a
{-# INLINE_PA filterPA_v #-}
filterPA_v pa p xs = packPA_v pa xs (mapPA_v pa dPA_Bool p xs)

filterPA_l :: PA a
           -> PArray (a :-> Bool) -> PArray (PArray a) -> PArray (PArray a)
{-# INLINE_PA filterPA_l #-}
filterPA_l pa ps xss = packPA_l pa xss (mapPA_l pa dPA_Bool ps xss)

filterPA :: PA a -> ((a :-> Bool) :-> PArray a :-> PArray a)
{-# INLINE filterPA #-}
filterPA pa = closure2 (dPA_Clo pa dPA_Bool) (filterPA_v pa) (filterPA_l pa)

indexPA_v :: PA a -> PArray a -> Int -> a
{-# INLINE_PA indexPA_v #-}
indexPA_v pa xs (I# i#) = indexPA# pa xs i#

indexPA_l :: PA a -> PArray (PArray a) -> PArray Int -> PArray a
{-# INLINE_PA indexPA_l #-}
indexPA_l pa (PNested _ lens idxs xs) (PInt n# is)
  = bpermutePA# pa n# xs (unsafe_zipWithPA_Int# (+) idxs is)

indexPA :: PA a -> (PArray a :-> Int :-> a)
{-# INLINE indexPA #-}
indexPA pa = closure2 (dPA_PArray pa) (indexPA_v pa) (indexPA_l pa)

concatPA_v :: PA a -> PArray (PArray a) -> PArray a
{-# INLINE_PA concatPA_v #-}
concatPA_v pa (PNested _ _ _ xs) = xs

concatPA_l :: PA a -> PArray (PArray (PArray a)) -> PArray (PArray a)
{-# INLINE_PA concatPA_l #-}
concatPA_l pa arr@(PNested m# lens1 idxs1 (PNested n# lens2 idxs2 xs))
  = PNested m# lens idxs xs
  where
    lens = sumPAs_Int# segd lens2
    idxs = bpermutePA_Int# idxs2 idxs1
    segd = segdOfPA# (dPA_PArray pa) arr

concatPA :: PA a -> (PArray (PArray a) :-> PArray a)
{-# INLINE concatPA #-}
concatPA pa = closure1 (concatPA_v pa) (concatPA_l pa)

appPA_v :: PA a -> PArray a -> PArray a -> PArray a
{-# INLINE_PA appPA_v #-}
appPA_v pa xs ys = appPA# pa xs ys

appPA_l :: PA a -> PArray (PArray a) -> PArray (PArray a) -> PArray (PArray a)
{-# INLINE_PA appPA_l #-}
appPA_l pa xss@(PNested m# lens1 idxs1 xs)
           yss@(PNested n# lens2 idxs2 ys)
  = PNested (m# +# n#) (unsafe_zipWithPA_Int# (+) lens1 lens2)
                       (unsafe_zipWithPA_Int# (+) idxs1 idxs2)
                       (applPA# pa (segdOfPA# pa xss) xs
                                   (segdOfPA# pa yss) ys)

appPA :: PA a -> (PArray a :-> PArray a :-> PArray a)
{-# INLINE appPA #-}
appPA pa = closure2 (dPA_PArray pa) (appPA_v pa) (appPA_l pa)


enumFromToPA_v :: Int -> Int -> PArray Int
{-# INLINE_PA enumFromToPA_v #-}
enumFromToPA_v m@(I# m#) n@(I# n#) = PInt len# (enumFromToPA_Int# m# n#)
  where
    !len# = max# 0# (n# -# m# +# 1#) -- case max 0 (n-m+1) of I# i# -> i#

max# :: Int# -> Int# -> Int#
{-# INLINE_STREAM max# #-}
max# m# n# = if m# <# n# then n# else m#

enumFromToPA_l :: PArray Int -> PArray Int -> PArray (PArray Int)
{-# INLINE_PA enumFromToPA_l #-}
enumFromToPA_l (PInt k# ms#) (PInt _ ns#) = PNested k# lens# idxs# (PInt n# is#)
  where
    lenOf m n = max 0 (n - m + 1)

    lens# = unsafe_zipWithPA_Int# lenOf ms# ns#
    idxs# = unsafe_scanPA_Int# (+) 0 lens#

    !n#   = sumPA_Int# lens#
    is#   = enumFromToEachPA_Int# n# ms# ns#

enumFromToPA_Int :: Int :-> Int :-> PArray Int
{-# INLINE enumFromToPA_Int #-}
enumFromToPA_Int = closure2 dPA_Int enumFromToPA_v enumFromToPA_l
