module Main ( main ) where

import Control.Arrow
import Control.Applicative
import Control.Monad.Identity
import Data.GraphViz
import Data.Monoid
import Options.Applicative

import LLVM.VisualizeGraph

import LLVM.Analysis
import LLVM.Analysis.CFG
import LLVM.Analysis.CDG
import LLVM.Analysis.CallGraph
import LLVM.Analysis.CallGraphSCCTraversal
import LLVM.Analysis.Dominance
import LLVM.Analysis.Escape
import LLVM.Analysis.PointsTo.TrivialFunction

data Opts = Opts { outputFile :: Maybe FilePath
                 , graphType :: GraphType
                 , outputFormat :: OutputType
                 , inputFile :: FilePath
                 }

cmdOpts :: Parser Opts
cmdOpts = Opts
 <$> option
     ( long "output"
     & short 'o'
     & metavar "FILE/DIR"
     & help "The destination of a file output"
     & value Nothing
     & reader (Just . auto))
  <*> option
      ( long "type"
      & short 't'
      & metavar "TYPE"
      & help "The graph requested.  One of Cfg, Cdg, Cg, Domtree, Postdomtree, Escape")
  <*> nullOption
      ( long "format"
      & short 'f'
      & metavar "FORMAT"
      & reader parseOutputType
      & help "The type of output to produce: Gtk, Xlib, XDot, Eps, Jpeg, Pdf, Png, Ps, Ps2, Svg.  Default: Gtk"
      & value (CanvasOutput Gtk))
  <*> argument str ( metavar "FILE" )

data GraphType = Cfg
               | Cdg
               | Cg
               | Domtree
               | Postdomtree
               | Escape
               deriving (Read, Show, Eq, Ord)

main :: IO ()
main = execParser args >>= realMain
  where
    args = info (helper <*> cmdOpts)
      ( fullDesc
      & progDesc "Generate the specified graph TYPE for FILE"
      & header "ViewIRGraph - View different graphs for LLVM IR modules in a variety of formats")

realMain :: Opts -> IO ()
realMain opts = do
  let gt = graphType opts
      inFile = inputFile opts
      outFile = outputFile opts
      fmt = outputFormat opts

  case gt of
    Cfg -> visualizeGraph inFile outFile fmt optOptions mkCFGs cfgGraphvizRepr
    Cdg -> visualizeGraph inFile outFile fmt optOptions mkCDGs cdgGraphvizRepr
    Cg -> visualizeGraph inFile outFile fmt optOptions mkCG cgGraphvizRepr
    Domtree -> visualizeGraph inFile outFile fmt optOptions mkDTs domTreeGraphvizRepr
    Postdomtree -> visualizeGraph inFile outFile fmt optOptions mkPDTs postdomTreeGraphvizRepr
    Escape -> visualizeGraph inFile outFile fmt optOptions mkEscapeGraphs useGraphvizRepr
  where
    optOptions = [ "-mem2reg", "-basicaa" ]

mkPDTs :: Module -> [(String, PostdominatorTree)]
mkPDTs m = map (getFuncName &&& toTree) fs
  where
    fs = moduleDefinedFunctions m
    toTree = postdominatorTree . reverseCFG . mkCFG

mkDTs :: Module -> [(String, DominatorTree)]
mkDTs m = map (getFuncName &&& toTree) fs
  where
    fs = moduleDefinedFunctions m
    toTree = dominatorTree . mkCFG

mkCG :: Module -> [(String, CallGraph)]
mkCG m = [("Module", mkCallGraph m aa [])]
  where
    aa = runPointsToAnalysis m

mkCFGs :: Module -> [(String, CFG)]
mkCFGs m = map (getFuncName &&& mkCFG) fs
  where
    fs = moduleDefinedFunctions m

mkCDGs :: Module -> [(String, CDG)]
mkCDGs m = map (getFuncName &&& toCDG) fs
  where
    fs = moduleDefinedFunctions m
    toCDG = controlDependenceGraph . mkCFG

runEscapeAnalysis ::  CallGraph
                     -> (ExternalFunction -> Int -> Identity Bool)
                     -> EscapeResult
runEscapeAnalysis cg extSumm =
  let analysis :: [Function] -> EscapeResult -> EscapeResult
      analysis = callGraphAnalysisM runIdentity (escapeAnalysis extSumm)
  in callGraphSCCTraversal cg analysis mempty

--mkEscapeGraphs :: Module -> [(String,
mkEscapeGraphs m = escapeUseGraphs er
  where
    er = runEscapeAnalysis cg (\_ _ -> return True)
    cg = mkCallGraph m pta []
    pta = runPointsToAnalysis m

getFuncName :: Function -> String
getFuncName = identifierAsString . functionName



-- Command line helpers


parseOutputType :: String -> Maybe OutputType
parseOutputType fmt =
  case fmt of
    "Html" -> Just HtmlOutput
    _ -> case reads fmt of
      [(Gtk, [])] -> Just $ CanvasOutput Gtk
      [(Xlib, [])] -> Just $ CanvasOutput Xlib
      _ -> case reads fmt of
        [(gout, [])] -> Just $ FileOutput gout
        _ -> Nothing
