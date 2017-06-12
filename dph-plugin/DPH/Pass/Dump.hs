
module DPH.Pass.Dump
        (passDump)
where
import DPH.Core.Pretty
import GHC.Types
import GHC.IR.Core.Pipeline
import System.IO.Unsafe

-- | Dump a module.
passDump :: String -> ModGuts -> CoreM ModGuts
passDump name guts
 = unsafePerformIO
 $ do
        writeFile ("dump." ++ name ++ ".hs")
         $ render RenderIndent (pprModGuts guts)

        return (return guts)
