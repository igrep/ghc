-- -----------------------------------------------------------------------------
-- $Id: System.lhs,v 1.37 2001/11/08 16:36:39 simonmar Exp $
--
-- (c) The University of Glasgow, 1994-2000
--

\begin{code}
#include "config.h"
module System 
    ( 
      ExitCode(ExitSuccess,ExitFailure)
    , getArgs	    -- :: IO [String]
    , getProgName   -- :: IO String
    , getEnv        -- :: String -> IO String
    , system        -- :: String -> IO ExitCode
    , exitWith      -- :: ExitCode -> IO a
    , exitFailure   -- :: IO a
  ) where

import Monad
import Prelude
import PrelCError
import PrelCString
import PrelCTypes
import PrelMarshalArray
import PrelMarshalAlloc
import PrelPtr
import PrelStorable
import PrelIOBase

-- ---------------------------------------------------------------------------
-- getArgs, getProgName, getEnv

-- Computation `getArgs' returns a list of the program's command
-- line arguments (not including the program name).

getArgs :: IO [String]
getArgs = 
  alloca $ \ p_argc ->  
  alloca $ \ p_argv -> do
   getProgArgv p_argc p_argv
   p    <- fromIntegral `liftM` peek p_argc
   argv <- peek p_argv
   peekArray (p - 1) (advancePtr argv 1) >>= mapM peekCString
   
   
foreign import "getProgArgv" unsafe 
  getProgArgv :: Ptr CInt -> Ptr (Ptr CString) -> IO ()

-- Computation `getProgName' returns the name of the program
-- as it was invoked.

getProgName :: IO String
getProgName = 
  alloca $ \ p_argc ->
  alloca $ \ p_argv -> do
     getProgArgv p_argc p_argv
     argv <- peek p_argv
     unpackProgName argv

-- Computation `getEnv var' returns the value
-- of the environment variable {\em var}.  

-- This computation may fail with
--    NoSuchThing: The environment variable does not exist.

getEnv :: String -> IO String
getEnv name =
    withCString name $ \s -> do
      litstring <- _getenv s
      if litstring /= nullPtr
	then peekCString litstring
        else ioException (IOError Nothing NoSuchThing "getEnv"
			  "no environment variable" (Just name))

foreign import ccall "getenv" unsafe _getenv :: CString -> IO (Ptr CChar)

-- ---------------------------------------------------------------------------
-- system

-- Computation `system cmd' returns the exit code
-- produced when the operating system processes the command {\em cmd}.

-- This computation may fail with
--   PermissionDenied 
--	The process has insufficient privileges to perform the operation.
--   ResourceExhausted
--      Insufficient resources are available to perform the operation.  
--   UnsupportedOperation
--	The implementation does not support system calls.

system :: String -> IO ExitCode
system "" = ioException (IOError Nothing InvalidArgument "system" "null command" Nothing)
system cmd =
  withCString cmd $ \s -> do
    status <- throwErrnoIfMinus1 "system" (primSystem s)
    case status of
        0  -> return ExitSuccess
        n  -> return (ExitFailure n)

foreign import ccall "systemCmd" unsafe primSystem :: CString -> IO Int

-- ---------------------------------------------------------------------------
-- exitWith

-- `exitWith code' terminates the program, returning `code' to the
-- program's caller.  Before it terminates, any open or semi-closed
-- handles are first closed.

exitWith :: ExitCode -> IO a
exitWith ExitSuccess = throw (ExitException ExitSuccess)
exitWith code@(ExitFailure n) 
  | n == 0 = ioException (IOError Nothing InvalidArgument "exitWith" "ExitFailure 0" Nothing)
  | otherwise = throw (ExitException code)

exitFailure :: IO a
exitFailure = exitWith (ExitFailure 1)

-- ---------------------------------------------------------------------------
-- Local utilities

unpackProgName	:: Ptr (Ptr CChar) -> IO String   -- argv[0]
unpackProgName argv = do 
  s <- peekElemOff argv 0 >>= peekCString
  return (basename s)
  where
   basename :: String -> String
   basename f = go f f
    where
      go acc [] = acc
      go acc (x:xs) 
        | isPathSeparator x = go xs xs
        | otherwise         = go acc xs

   isPathSeparator :: Char -> Bool
   isPathSeparator '/'  = True
#ifdef mingw32_TARGET_OS 
   isPathSeparator '\\' = True
#endif
   isPathSeparator _    = False

\end{code}
