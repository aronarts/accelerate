{-# LANGUAGE TypeOperators, FlexibleContexts, TypeFamilies, RankNTypes, ScopedTypeVariables #-}
{-# LANGUAGE FlexibleInstances, MultiParamTypeClasses #-}
{-# OPTIONS_GHC -fno-warn-missing-methods #-}
-- |
-- Module      : Data.Array.Accelerate.Language
-- Copyright   : [2009..2010] Manuel M T Chakravarty, Gabriele Keller, Sean Lee
-- License     : BSD3
--
-- Maintainer  : Manuel M T Chakravarty <chak@cse.unsw.edu.au>
-- Stability   : experimental
-- Portability : non-portable (GHC extensions)
--
-- We use the dictionary view of overloaded operations (such as arithmetic and
-- bit manipulation) to reify such expressions.  With non-overloaded
-- operations (such as, the logical connectives) and partially overloaded
-- operations (such as comparisons), we use the standard operator names with a
-- '*' attached.  We keep the standard alphanumeric names as they can be
-- easily qualified.

module Data.Array.Accelerate.Language (

  -- ** Array and scalar expressions
  Acc, Exp,                                 -- re-exporting from 'Smart'
  
  -- ** Stencil specification
  Boundary(..), Stencil,                    -- re-exporting from 'Smart'

  -- ** Common stencil types
  Stencil3, Stencil5, Stencil7, Stencil9,
  Stencil3x3, Stencil5x3, Stencil3x5, Stencil5x5,
  Stencil3x3x3, Stencil5x3x3, Stencil3x5x3, Stencil3x3x5, Stencil5x5x3, Stencil5x3x5,
  Stencil3x5x5, Stencil5x5x5,

  -- ** Scalar introduction
  constant,                                 -- re-exporting from 'Smart'

  -- ** Array construction
  use, unit, replicate, generate,

  -- ** Shape manipulation
  reshape,

  -- ** Extraction of subarrays
  slice, 
  
  -- ** Map-like functions
  map, zipWith,
  
  -- ** Reductions
  fold, fold1, foldSeg, fold1Seg,
  
  -- ** Scan functions
  scanl, scanl', scanl1, scanr, scanr', scanr1,
  
  -- ** Permutations
  permute, backpermute, 
  
  -- ** Stencil operations
  stencil, stencil2,
  
  -- ** Tuple construction and destruction
  Tuple(..), fst, snd, curry, uncurry,
  
  -- ** Index expressions
  Index(..), index0, index1, unindex1, ilift1,
  
  -- ** Conditional expressions
  (?),
  
  -- ** Array operations with a scalar result
  (!), the, shape, size,
  
  -- ** Methods of H98 classes that we need to redefine as their signatures change
  (==*), (/=*), (<*), (<=*), (>*), (>=*), max, min,
  bit, setBit, clearBit, complementBit, testBit,
  shift,  shiftL,  shiftR,
  rotate, rotateL, rotateR,

  -- ** Standard functions that we need to redefine as their signatures change
  (&&*), (||*), not,
  
  -- ** Conversions
  boolToInt, intToFloat, roundFloatToInt, truncateFloatToInt,

  -- ** Constants
  ignore

  -- ** Instances of Bounded, Enum, Eq, Ord, Bits, Num, Real, Floating,
  --    Fractional, RealFrac, RealFloat

) where

-- avoid clashes with Prelude functions
import Prelude   hiding (replicate, zip, unzip, map, scanl, scanl1, scanr, scanr1, zipWith,
                         filter, max, min, not, const, fst, snd, curry, uncurry)

-- standard libraries
import Data.Bits (Bits((.&.), (.|.), xor, complement))

-- friends
import Data.Array.Accelerate.Type
import Data.Array.Accelerate.Array.Sugar hiding ((!), ignore, shape, size, index)
import qualified Data.Array.Accelerate.Array.Sugar as Sugar
import Data.Array.Accelerate.Smart


-- Array introduction
-- ------------------

-- |Array inlet: makes an array available for processing using the Accelerate
-- language; triggers asynchronous host->device transfer if necessary.
--
use :: (Shape ix, Elt e) => Array ix e -> Acc (Array ix e)
use = Acc . Use

-- |Scalar inlet: injects a scalar (or a tuple of scalars) into a singleton
-- array for use in the Accelerate language.
--
unit :: Elt e => Exp e -> Acc (Scalar e)
unit = Acc . Unit

-- |Replicate an array across one or more dimensions as specified by the
-- *generalised* array index provided as the first argument.
--
-- For example, assuming 'arr' is a vector (one-dimensional array),
--
-- > replicate (Z :.2 :.All :.3) arr
--
-- yields a three dimensional array, where 'arr' is replicated twice across the
-- first and three times across the third dimension.
--
replicate :: (Slice slix, Elt e) 
          => Exp slix 
          -> Acc (Array (SliceShape slix) e) 
          -> Acc (Array (FullShape  slix) e)
replicate = Acc $$ Replicate

-- |Construct a new array by applying a function to each index.
--
generate :: (Shape ix, Elt a)
         => Exp ix
         -> (Exp ix -> Exp a)
         -> Acc (Array ix a)
generate = Acc $$ Generate

-- Shape manipulation
-- ------------------

-- |Change the shape of an array without altering its contents, where
--
-- > precondition: size ix == size ix'
--
reshape :: (Shape ix, Shape ix', Elt e) 
        => Exp ix 
        -> Acc (Array ix' e) 
        -> Acc (Array ix e)
reshape = Acc $$ Reshape

-- Extraction of subarrays
-- -----------------------

-- |Index an array with a *generalised* array index (supplied as the second
-- argument).  The result is a new array (possibly a singleton) containing
-- all dimensions in their entirety.
--
slice :: (Slice slix, Elt e) 
      => Acc (Array (FullShape slix) e) 
      -> Exp slix 
      -> Acc (Array (SliceShape slix) e)
slice = Acc $$ Index

-- Map-like functions
-- ------------------

-- |Apply the given function elementwise to the given array.
-- 
map :: (Shape ix, Elt a, Elt b) 
    => (Exp a -> Exp b) 
    -> Acc (Array ix a)
    -> Acc (Array ix b)
map = Acc $$ Map

-- |Apply the given binary function elementwise to the two arrays.  The extent of the resulting
-- array is the intersection of the extents of the two source arrays.
--
zipWith :: (Shape ix, Elt a, Elt b, Elt c)
        => (Exp a -> Exp b -> Exp c) 
        -> Acc (Array ix a)
        -> Acc (Array ix b)
        -> Acc (Array ix c)
zipWith = Acc $$$ ZipWith

-- Reductions
-- ----------

-- |Reduction of the innermost dimension of an array of arbitrary rank.  The first argument needs to
-- be an /associative/ function to enable an efficient parallel implementation.
-- 
fold :: (Shape ix, Elt a)
     => (Exp a -> Exp a -> Exp a) 
     -> Exp a 
     -> Acc (Array (ix:.Int) a)
     -> Acc (Array ix a)
fold = Acc $$$ Fold

-- |Variant of 'fold' that requires the reduced array to be non-empty and doesn't need an default
-- value.
-- 
fold1 :: (Shape ix, Elt a)
      => (Exp a -> Exp a -> Exp a) 
      -> Acc (Array (ix:.Int) a)
      -> Acc (Array ix a)
fold1 = Acc $$ Fold1

-- |Segmented reduction along the innermost dimension.  Performs one individual reduction per
-- segment of the source array.  These reductions proceed in parallel.
--
-- The source array must have at least rank 1.
--
foldSeg :: (Shape ix, Elt a)
        => (Exp a -> Exp a -> Exp a) 
        -> Exp a 
        -> Acc (Array (ix:.Int) a)
        -> Acc Segments
        -> Acc (Array (ix:.Int) a)
foldSeg = Acc $$$$ FoldSeg

-- |Variant of 'foldSeg' that requires /all/ segments of the reduced array to be non-empty and
-- doesn't need a default value.
--
-- The source array must have at least rank 1.
--
fold1Seg :: (Shape ix, Elt a)
         => (Exp a -> Exp a -> Exp a) 
         -> Acc (Array (ix:.Int) a)
         -> Acc Segments
         -> Acc (Array (ix:.Int) a)
fold1Seg = Acc $$$ Fold1Seg

-- Scan functions
-- --------------

-- |'Data.List'-style left-to-right scan, but with the additional restriction that the first argument
-- needs to be an /associative/ function to enable an efficient parallel implementation.  The initial
-- value (second argument) may be aribitrary.
--
scanl :: Elt a
      => (Exp a -> Exp a -> Exp a)
      -> Exp a
      -> Acc (Vector a)
      -> Acc (Vector a)
scanl = Acc $$$ Scanl

-- |Variant of 'scanl', where the final result of the reduction is returned separately. 
-- Denotationally, we have
--
-- > scanl' f e arr = (crop 0 (len - 1) res, unit (res!len))
-- >   where
-- >     len = shape arr
-- >     res = scanl f e arr in 
--
scanl' :: Elt a
       => (Exp a -> Exp a -> Exp a)
       -> Exp a
       -> Acc (Vector a)
       -> (Acc (Vector a), Acc (Scalar a))
scanl' = unpair . Acc $$$ Scanl'

-- |'Data.List' style left-to-right scan without an intial value (aka inclusive scan).  Again, the
-- first argument needs to be an /associative/ function.  Denotationally, we have
--
-- > scanl1 f e arr = crop 1 len res
-- >   where
-- >     len = shape arr
-- >     res = scanl f e arr in 
--
scanl1 :: Elt a
       => (Exp a -> Exp a -> Exp a)
       -> Acc (Vector a)
       -> Acc (Vector a)
scanl1 = Acc $$ Scanl1

-- |Right-to-left variant of 'scanl'.
--
scanr :: Elt a
      => (Exp a -> Exp a -> Exp a)
      -> Exp a
      -> Acc (Vector a)
      -> Acc (Vector a)
scanr = Acc $$$ Scanr

-- |Right-to-left variant of 'scanl\''. 
--
scanr' :: Elt a
       => (Exp a -> Exp a -> Exp a)
       -> Exp a
       -> Acc (Vector a)
       -> (Acc (Vector a), Acc (Scalar a))
scanr' = unpair . Acc $$$ Scanr'

-- |Right-to-left variant of 'scanl1'.
--
scanr1 :: Elt a
       => (Exp a -> Exp a -> Exp a)
       -> Acc (Vector a)
       -> Acc (Vector a)
scanr1 = Acc $$ Scanr1

-- Permutations
-- ------------

-- |Forward permutation specified by an index mapping.  The result array is
-- initialised with the given defaults and any further values that are permuted
-- into the result array are added to the current value using the given
-- combination function.
--
-- The combination function must be /associative/.  Eltents that are mapped to
-- the magic value 'ignore' by the permutation function are being dropped.
--
permute :: (Shape ix, Shape ix', Elt a)
        => (Exp a -> Exp a -> Exp a)    -- ^combination function
        -> Acc (Array ix' a)            -- ^array of default values
        -> (Exp ix -> Exp ix')          -- ^permutation
        -> Acc (Array ix  a)            -- ^permuted array
        -> Acc (Array ix' a)
permute = Acc $$$$ Permute

-- |Backward permutation 
--
backpermute :: (Shape ix, Shape ix', Elt a)
            => Exp ix'                  -- ^shape of the result array
            -> (Exp ix' -> Exp ix)      -- ^permutation
            -> Acc (Array ix  a)        -- ^permuted array
            -> Acc (Array ix' a)
backpermute = Acc $$$ Backpermute

-- Stencil operations
-- ------------------

-- Common stencil types
--

-- DIM1 stencil type
type Stencil3 a = (Exp a, Exp a, Exp a)
type Stencil5 a = (Exp a, Exp a, Exp a, Exp a, Exp a)
type Stencil7 a = (Exp a, Exp a, Exp a, Exp a, Exp a, Exp a, Exp a)
type Stencil9 a = (Exp a, Exp a, Exp a, Exp a, Exp a, Exp a, Exp a, Exp a, Exp a)

-- DIM2 stencil type
type Stencil3x3 a = (Stencil3 a, Stencil3 a, Stencil3 a)
type Stencil5x3 a = (Stencil5 a, Stencil5 a, Stencil5 a)
type Stencil3x5 a = (Stencil3 a, Stencil3 a, Stencil3 a, Stencil3 a, Stencil3 a)
type Stencil5x5 a = (Stencil5 a, Stencil5 a, Stencil5 a, Stencil5 a, Stencil5 a)

-- DIM3 stencil type
type Stencil3x3x3 a = (Stencil3x3 a, Stencil3x3 a, Stencil3x3 a)
type Stencil5x3x3 a = (Stencil5x3 a, Stencil5x3 a, Stencil5x3 a)
type Stencil3x5x3 a = (Stencil3x5 a, Stencil3x5 a, Stencil3x5 a)
type Stencil3x3x5 a = (Stencil3x3 a, Stencil3x3 a, Stencil3x3 a, Stencil3x3 a, Stencil3x3 a)
type Stencil5x5x3 a = (Stencil5x5 a, Stencil5x5 a, Stencil5x5 a)
type Stencil5x3x5 a = (Stencil5x3 a, Stencil5x3 a, Stencil5x3 a, Stencil5x3 a, Stencil5x3 a)
type Stencil3x5x5 a = (Stencil3x5 a, Stencil3x5 a, Stencil3x5 a, Stencil3x5 a, Stencil3x5 a)
type Stencil5x5x5 a = (Stencil5x5 a, Stencil5x5 a, Stencil5x5 a, Stencil5x5 a, Stencil5x5 a)

-- |Map a stencil over an array.  In contrast to 'map', the domain of a stencil function is an
--  entire /neighbourhood/ of each array element.  Neighbourhoods are sub-arrays centred around a
--  focal point.  They are not necessarily rectangular, but they are symmetric in each dimension
--  and have an extent of at least three in each dimensions — due to the symmetry requirement, the
--  extent is necessarily odd.  The focal point is the array position that is determined by the
--  stencil.
--
--  For those array positions where the neighbourhood extends past the boundaries of the source
--  array, a boundary condition determines the contents of the out-of-bounds neighbourhood
--  positions.
--
stencil :: (Shape ix, Elt a, Elt b, Stencil ix a stencil)
        => (stencil -> Exp b)                 -- ^stencil function
        -> Boundary a                         -- ^boundary condition
        -> Acc (Array ix a)                   -- ^source array
        -> Acc (Array ix b)                   -- ^destination array
stencil = Acc $$$ Stencil

-- |Map a binary stencil of an array.  The extent of the resulting array is the intersection of
-- the extents of the two source arrays.
--
stencil2 :: (Shape ix, Elt a, Elt b, Elt c, 
             Stencil ix a stencil1, 
             Stencil ix b stencil2)
        => (stencil1 -> stencil2 -> Exp c)    -- ^binary stencil function
        -> Boundary a                         -- ^boundary condition #1
        -> Acc (Array ix a)                   -- ^source array #1
        -> Boundary b                         -- ^boundary condition #2
        -> Acc (Array ix b)                   -- ^source array #2
        -> Acc (Array ix c)                   -- ^destination array
stencil2 = Acc $$$$$ Stencil2


-- Tuples
-- ------

class Tuple tup where
  type TupleT tup

  -- |Turn a tuple of scalar expressions into a scalar expressions that yields
  -- a tuple.
  -- 
  tuple   :: tup -> TupleT tup
  
  -- |Turn a scalar expression that yields a tuple into a tuple of scalar
  -- expressions.
  --
  untuple :: TupleT tup -> tup
  
instance (Elt a, Elt b) => Tuple (Exp a, Exp b) where
  type TupleT (Exp a, Exp b) = Exp (a, b)
  tuple   = tup2
  untuple = untup2

instance (Elt a, Elt b, Elt c) => Tuple (Exp a, Exp b, Exp c) where
  type TupleT (Exp a, Exp b, Exp c) = Exp (a, b, c)
  tuple   = tup3
  untuple = untup3

instance (Elt a, Elt b, Elt c, Elt d) 
  => Tuple (Exp a, Exp b, Exp c, Exp d) where
  type TupleT (Exp a, Exp b, Exp c, Exp d) = Exp (a, b, c, d)
  tuple   = tup4
  untuple = untup4

instance (Elt a, Elt b, Elt c, Elt d, Elt e) 
  => Tuple (Exp a, Exp b, Exp c, Exp d, Exp e) where
  type TupleT (Exp a, Exp b, Exp c, Exp d, Exp e) = Exp (a, b, c, d, e)
  tuple   = tup5
  untuple = untup5

instance (Elt a, Elt b, Elt c, Elt d, Elt e, Elt f)
  => Tuple (Exp a, Exp b, Exp c, Exp d, Exp e, Exp f) where
  type TupleT (Exp a, Exp b, Exp c, Exp d, Exp e, Exp f)
    = Exp (a, b, c, d, e, f)
  tuple   = tup6
  untuple = untup6

instance (Elt a, Elt b, Elt c, Elt d, Elt e, Elt f, Elt g)
  => Tuple (Exp a, Exp b, Exp c, Exp d, Exp e, Exp f, Exp g) where
  type TupleT (Exp a, Exp b, Exp c, Exp d, Exp e, Exp f, Exp g)
    = Exp (a, b, c, d, e, f, g)
  tuple   = tup7
  untuple = untup7

instance (Elt a, Elt b, Elt c, Elt d, Elt e, Elt f, Elt g, Elt h)
  => Tuple (Exp a, Exp b, Exp c, Exp d, Exp e, Exp f, Exp g, Exp h) where
  type TupleT (Exp a, Exp b, Exp c, Exp d, Exp e, Exp f, Exp g, Exp h)
    = Exp (a, b, c, d, e, f, g, h)
  tuple   = tup8
  untuple = untup8

instance (Elt a, Elt b, Elt c, Elt d, Elt e, Elt f, Elt g, Elt h, Elt i)
  => Tuple (Exp a, Exp b, Exp c, Exp d, Exp e, Exp f, Exp g, Exp h, Exp i) where
  type TupleT (Exp a, Exp b, Exp c, Exp d, Exp e, Exp f, Exp g, Exp h, Exp i)
    = Exp (a, b, c, d, e, f, g, h, i)
  tuple   = tup9
  untuple = untup9

-- |Extract the first component of a pair
--
fst :: forall a b. (Elt a, Elt b) => Exp (a, b) -> Exp a
fst e = let (x, _:: Exp b) = untuple e in x

-- |Extract the second component of a pair
--
snd :: forall a b. (Elt a, Elt b) => Exp (a, b) -> Exp b
snd e = let (_ :: Exp a, y) = untuple e in y

-- |Converts an uncurried function to a curried function
--
curry :: (Elt a, Elt b) => (Exp (a, b) -> Exp c) -> Exp a -> Exp b -> Exp c
curry f x y = f (tuple (x, y))

-- |Converts a curried function to a function on pairs
--
uncurry :: (Elt a, Elt b) => (Exp a -> Exp b -> Exp c) -> Exp (a, b) -> Exp c
uncurry f t = let (x, y) = untuple t in f x y


-- Shapes
-- ------

class Index ix where
  type IndexExp ix
  
  -- |Turn an index into a scalar Accelerate expression yielding that index.
  -- 
  index   :: IndexExp ix -> Exp ix
  
  -- |Turn a scalar Accelerate expression that yields an index into an index structure of scalar
  -- expressions.
  --
  unindex :: Exp ix -> IndexExp ix
  
instance Index Z where
  type IndexExp Z = Z

  index _   = IndexNil
  unindex _ = Z
  
instance (Shape ix, Index ix) => Index (ix:.Int) where
  type IndexExp (ix:.Int) = IndexExp ix :. Exp Int

  index (ix:.i) = IndexCons (index ix) i
  unindex e     = unindex (IndexTail e) :. IndexHead e

-- |The one index for a rank-0 array.
--
index0 :: Exp Z
index0 = index Z

-- |Turn an 'Int' expression into a rank-1 indexing expression.
--
index1 :: Exp Int -> Exp (Z:. Int)
index1 = index . (Z:.)

-- |Turn an 'Int' expression into a rank-1 indexing expression.
--
unindex1 :: Exp (Z:. Int) -> Exp Int
unindex1 ix = let Z:.i = unindex ix in i

-- |Lift an Accelerate integer computation into rank-1 index space.
--
ilift1 :: (Exp Int -> Exp Int) -> Exp (Z:. Int) -> Exp (Z:. Int)
ilift1 f = index1 . f . unindex1
  

-- Conditional expressions
-- -----------------------

-- |Conditional expression.
--
infix 0 ?
(?) :: Elt t => Exp Bool -> (Exp t, Exp t) -> Exp t
c ? (t, e) = Cond c t e


-- Array operations with a scalar result
-- -------------------------------------

-- |Expression form that extracts a scalar from an array.
--
infixl 9 !
(!) :: (Shape ix, Elt e) => Acc (Array ix e) -> Exp ix -> Exp e
(!) = IndexScalar

-- |Extraction of the element in a singleton array.
--
the :: Elt e => Acc (Scalar e) -> Exp e
the = (!index0)

-- |Expression form that yields the shape of an array.
--
shape :: (Shape ix, Elt e) => Acc (Array ix e) -> Exp ix
shape = Shape

-- |Expression form that yields the size of an array.
--
size :: (Shape ix, Elt e) => Acc (Array ix e) -> Exp Int
size = Size


-- Instances of all relevant H98 classes
-- -------------------------------------

instance (Elt t, IsBounded t) => Bounded (Exp t) where
  minBound = mkMinBound
  maxBound = mkMaxBound

instance (Elt t, IsScalar t) => Enum (Exp t)
--  succ = mkSucc
--  pred = mkPred
  -- FIXME: ops

instance (Elt t, IsScalar t) => Prelude.Eq (Exp t) where
  -- FIXME: instance makes no sense with standard signatures
  (==)        = error "Prelude.Eq.== applied to EDSL types"

instance (Elt t, IsScalar t) => Prelude.Ord (Exp t) where
  -- FIXME: instance makes no sense with standard signatures
  compare     = error "Prelude.Ord.compare applied to EDSL types"

instance (Elt t, IsNum t, IsIntegral t) => Bits (Exp t) where
  (.&.)      = mkBAnd
  (.|.)      = mkBOr
  xor        = mkBXor
  complement = mkBNot
  -- FIXME: argh, the rest have fixed types in their signatures

shift, shiftL, shiftR :: (Elt t, IsIntegral t) => Exp t -> Exp Int -> Exp t
shift  x i = i ==* 0 ? (x, i <* 0 ? (x `shiftR` (-i), x `shiftL` i))
shiftL     = mkBShiftL
shiftR     = mkBShiftR

rotate, rotateL, rotateR :: (Elt t, IsIntegral t) => Exp t -> Exp Int -> Exp t
rotate  x i = i ==* 0 ? (x, i <* 0 ? (x `rotateR` (-i), x `rotateL` i))
rotateL     = mkBRotateL
rotateR     = mkBRotateR

bit :: (Elt t, IsIntegral t) => Exp Int -> Exp t
bit x = 1 `shiftL` x

setBit, clearBit, complementBit :: (Elt t, IsIntegral t) => Exp t -> Exp Int -> Exp t
x `setBit` i        = x .|. bit i
x `clearBit` i      = x .&. complement (bit i)
x `complementBit` i = x `xor` bit i

testBit :: (Elt t, IsIntegral t) => Exp t -> Exp Int -> Exp Bool
x `testBit` i       = (x .&. bit i) /=* 0


instance (Elt t, IsNum t) => Num (Exp t) where
  (+)         = mkAdd
  (-)         = mkSub
  (*)         = mkMul
  negate      = mkNeg
  abs         = mkAbs
  signum      = mkSig
  fromInteger = constant . fromInteger

instance (Elt t, IsNum t) => Real (Exp t)
  -- FIXME: Why did we include this class?  We won't need `toRational' until
  --   we support rational numbers in AP computations.

instance (Elt t, IsIntegral t) => Integral (Exp t) where
  quot = mkQuot
  rem  = mkRem
  div  = mkIDiv
  mod  = mkMod
--  quotRem =
--  divMod  =
--  toInteger =  -- makes no sense

instance (Elt t, IsFloating t) => Floating (Exp t) where
  pi      = mkPi
  sin     = mkSin
  cos     = mkCos
  tan     = mkTan
  asin    = mkAsin
  acos    = mkAcos
  atan    = mkAtan
  asinh   = mkAsinh
  acosh   = mkAcosh
  atanh   = mkAtanh
  exp     = mkExpFloating
  sqrt    = mkSqrt
  log     = mkLog
  (**)    = mkFPow
  logBase = mkLogBase
  -- FIXME: add other ops

instance (Elt t, IsFloating t) => Fractional (Exp t) where
  (/)          = mkFDiv
  recip        = mkRecip
  fromRational = constant . fromRational
  -- FIXME: add other ops

instance (Elt t, IsFloating t) => RealFrac (Exp t)
  -- FIXME: add ops

instance (Elt t, IsFloating t) => RealFloat (Exp t) where
  atan2 = mkAtan2
  -- FIXME: add ops


-- Methods from H98 classes, where we need other signatures
-- --------------------------------------------------------

infix 4 ==*, /=*, <*, <=*, >*, >=*

-- |Equality lifted into Accelerate expressions.
--
(==*) :: (Elt t, IsScalar t) => Exp t -> Exp t -> Exp Bool
(==*) = mkEq

-- |Inequality lifted into Accelerate expressions.
--
(/=*) :: (Elt t, IsScalar t) => Exp t -> Exp t -> Exp Bool
(/=*) = mkNEq

-- compare :: a -> a -> Ordering  -- we have no enumerations at the moment
-- compare = ...

-- |Smaller-than lifted into Accelerate expressions.
--
(<*) :: (Elt t, IsScalar t) => Exp t -> Exp t -> Exp Bool
(<*)  = mkLt

-- |Greater-or-equal lifted into Accelerate expressions.
--
(>=*) :: (Elt t, IsScalar t) => Exp t -> Exp t -> Exp Bool
(>=*) = mkGtEq

-- |Greater-than lifted into Accelerate expressions.
--
(>*) :: (Elt t, IsScalar t) => Exp t -> Exp t -> Exp Bool
(>*)  = mkGt

-- |Smaller-or-equal lifted into Accelerate expressions.
--
(<=*) :: (Elt t, IsScalar t) => Exp t -> Exp t -> Exp Bool
(<=*) = mkLtEq

-- |Determine the maximum of two scalars.
--
max :: (Elt t, IsScalar t) => Exp t -> Exp t -> Exp t
max = mkMax

-- |Determine the minimum of two scalars.
--
min :: (Elt t, IsScalar t) => Exp t -> Exp t -> Exp t
min = mkMin


-- Non-overloaded standard functions, where we need other signatures
-- -----------------------------------------------------------------

-- |Conjunction
--
infixr 3 &&*
(&&*) :: Exp Bool -> Exp Bool -> Exp Bool
(&&*) = mkLAnd

-- |Disjunction
--
infixr 2 ||*
(||*) :: Exp Bool -> Exp Bool -> Exp Bool
(||*) = mkLOr

-- |Negation
--
not :: Exp Bool -> Exp Bool
not = mkLNot


-- Conversions
-- -----------

-- |Convert a Boolean value to an 'Int', where 'False' turns into '0' and 'True'
-- into '1'.
-- 
boolToInt :: Exp Bool -> Exp Int
boolToInt = mkBoolToInt

-- |Convert an Int to a Float
--
intToFloat :: Exp Int -> Exp Float
intToFloat = mkIntFloat

-- |Round Float to Int
--
roundFloatToInt :: Exp Float -> Exp Int
roundFloatToInt = mkRoundFloatInt

-- |Truncate Float to Int
--
truncateFloatToInt :: Exp Float -> Exp Int
truncateFloatToInt = mkTruncFloatInt


-- Constants
-- ---------

-- |Magic value identifying elements that are ignored in a forward permutation
--
ignore :: Shape ix => Exp ix
ignore = constant Sugar.ignore
