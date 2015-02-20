
module Test.Command(main) where

import Development.Shake
import Development.Shake.FilePath
import System.Time.Extra
import Control.Monad.Extra
import System.Directory
import Test.Type
import System.Exit
import Data.List.Extra


main = shaken test $ \args obj -> do
    let helper = [toNative $ obj "shake_helper" <.> exe]
    let name !> test = do want [name | null args || name `elem` args]
                          name ~> do need [obj "shake_helper" <.> exe]; test

    let helper_source = unlines
            ["import Control.Concurrent"
            ,"import Control.Monad"
            ,"import System.Directory"
            ,"import System.Environment"
            ,"import System.Exit"
            ,"import System.IO"
            ,"main = do"
            ,"    args <- getArgs"
            ,"    forM_ args $ \\(a:rg) -> case a of"
            ,"        'o' -> putStrLn rg"
            ,"        'e' -> hPutStrLn stderr rg"
            ,"        'f' -> do hFlush stdout; hFlush stderr"
            ,"        'x' -> exitFailure"
            ,"        'c' -> putStrLn =<< getCurrentDirectory"
            ,"        'v' -> putStrLn =<< getEnv rg"
            ,"        'w' -> threadDelay $ floor $ 1000000 * (read rg :: Double)"
            ]

    obj "shake_helper.hs" %> \out -> do need ["src/Test/Command.hs"]; writeFileChanged out helper_source
    obj "shake_helper" <.> exe %> \out -> do need [obj "shake_helper.hs"]; cmd (Cwd $ obj "") "ghc --make" "shake_helper.hs -o shake_helper"

    "capture" !> do
        (Stderr err, Stdout out) <- cmd helper ["ostuff goes here","eother stuff here"]
        liftIO $ out === "stuff goes here\n"
        liftIO $ err === "other stuff here\n"
        Stdouterr out <- cmd helper Shell "o1 f w0.5 e2 o3"
        liftIO $ out === "1\n2\n3\n"

    "failure" !> do
        (Exit e, Stdout (), Stderr ()) <- cmd helper "oo ee x"
        when (e == ExitSuccess) $ error "/= ExitSuccess"
        liftIO $ assertException ["BAD"] $ cmd helper "oo eBAD x" (EchoStdout False) (EchoStderr False)

    "cwd" !> do
        Stdout out <- cmd (Cwd $ obj "") helper "c"
        liftIO $ (===) (trim out) =<< canonicalizePath (dropTrailingPathSeparator $ obj "")

    "timeout" !> do
        offset <- liftIO offsetTime
        Exit exit <- cmd (Timeout 2) helper "w20"
        t <- liftIO offset
        putNormal $ "Timed out in " ++ showDuration t
        when (exit == ExitSuccess) $ error "== ExitSuccess"
        when (t < 2 || t > 8) $ error $ "failed to timeout, took " ++ show t

    "env" !> do
        -- use liftIO since it blows away PATH which makes lint-tracker stop working
        Stdout out <- liftIO $ cmd (Env [("FOO","HELLO SHAKE")]) Shell helper "vFOO"
        liftIO $ out === "HELLO SHAKE\n"

    "path" !> do
        path <- addPath [dropTrailingPathSeparator $ obj ""] []
        unit $ cmd $ obj "shake_helper"
        unit $ cmd $ obj "shake_helper" <.> exe
        unit $ cmd path Shell "shake_helper"
        unit $ cmd path "shake_helper"


test build obj = do
    -- reduce the overhead by running all the tests in parallel
    build ["-j4"]
