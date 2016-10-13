{-# LANGUAGE CPP #-}
-- |
-- Module      : Data.Array.Accelerate.Debug.Timed
-- Copyright   : [2016] Manuel M T Chakravarty, Gabriele Keller, Trevor L. McDonell
-- License     : BSD3
--
-- Maintainer  : Trevor L. McDonell <tmcdonell@cse.unsw.edu.au>
-- Stability   : experimental
-- Portability : non-portable (GHC extensions)
--

module Data.Array.Accelerate.Debug.Timed (

  timed,

) where

import Data.Array.Accelerate.Debug.Trace
import Data.Array.Accelerate.Debug.Flags

import Data.Int
import Data.List
import Data.Time.Clock
import System.CPUTime
import Text.Printf

import GHC.Stats


-- | Execute an action and time the results. If GC stats have been enabled (with
-- @+RTS -t@ for example) then timing and memory usage information is displayed,
-- otherwise only timing information is shown.
--
timed :: Mode -> ShowS -> IO a -> IO a
#ifdef ACCELERATE_DEBUG
timed mode fmt action = do
  enabled <- queryFlag mode
  if enabled
    then do
      with_gc <- getGCStatsEnabled
      if with_gc
        then timed_gc    fmt action
        else timed_simpl fmt action
    else
      action
#else
timed _ _ action = action
#endif


timed_simpl :: ShowS -> IO a -> IO a
timed_simpl fmt action = do
  wall0 <- getCurrentTime
  cpu0  <- getCPUTime
  res   <- action
  wall1 <- getCurrentTime
  cpu1  <- getCPUTime
  --
  let wallTime = realToFrac (diffUTCTime wall1 wall0)
      cpuTime  = fromIntegral (cpu1 - cpu0) * 1E-12
  --
  putTraceMsg (fmt (elapsed wallTime cpuTime))
  return res


timed_gc :: ShowS -> IO a -> IO a
timed_gc fmt action = do
  gc0 <- getGCStats
  res <- action
  gc1 <- getGCStats
  --
  let toDouble :: Int64 -> Double
      toDouble    = fromIntegral
      --
      allocated   = toDouble (bytesAllocated gc1 - bytesAllocated gc0)
      copied      = toDouble (bytesCopied gc1 - bytesCopied gc0)
      totalWall   = wallSeconds gc1 - wallSeconds gc0
      totalCPU    = cpuSeconds gc1 - cpuSeconds gc0
      mutatorWall = mutatorWallSeconds gc1 - mutatorWallSeconds gc0
      mutatorCPU  = mutatorCpuSeconds gc1 - mutatorCpuSeconds gc0
      gcWall      = gcWallSeconds gc1 - gcWallSeconds gc0
      gcCPU       = gcCpuSeconds gc1 - gcCpuSeconds gc0

  putTraceMsg . fmt $ intercalate "\n"
    [ elapsed totalWall totalCPU
    , printf "    %s allocated on the heap" (showFFloatSIBase (Just 1) 1024 allocated "B")
    , printf "    %s copied during GC (%d collections)" (showFFloatSIBase (Just 1) 1024 copied "B") (numGcs gc1 - numGcs gc0)
    , printf "    MUT: %s" (elapsed mutatorWall mutatorCPU)
    , printf "    GC:  %s" (elapsed gcWall gcCPU)
    ]
  --
  return res


elapsed :: Double -> Double -> String
elapsed wallTime cpuTime =
  printf "%s (wall), %s (cpu)"
    (showFFloatSIBase (Just 3) 1000 wallTime "s")
    (showFFloatSIBase (Just 3) 1000 cpuTime  "s")

