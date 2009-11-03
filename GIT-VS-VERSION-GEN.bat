@ECHO OFF
REM  Script for generation of rc VERSIONINFO & StringFileInfo

:: VERSION_FILE - Untracked file to be included in packaged source releases.
:: it should contain a single line in the format:
::    $Project_Name VERSION $tag ( ie: Foobar VERSION v1.0.0-alpha0 )
SET VERSION_FILE=GIT-VS-VERSION-FILE

:: Arguments
IF "%1" == "-f" (
  SET FORCE=1
  SHIFT
) ELSE (
  IF "%1" == "--force" (
    SET FORCE=1
    SHIFT
  )
)

:: Cache file
IF [%1] EQU [] (
  GOTO USAGE
) ELSE (
  IF [%~nx1] NEQ [] (
    IF [%~2] NEQ [] GOTO USAGE
    GOTO SET_OUT
  )
  SET CACHE_FILE=%~1\%VERSION_FILE%
  SHIFT
)

:SET_OUT
:: File Version Info out file.
IF [%1] EQU [] (
  GOTO USAGE
) ELSE (
  IF [%~nx1] EQU [] GOTO USAGE
  SET HEADER_OUT_FILE="%~1"
)

:: DEFAULT_VERSION - Used when built from source that was downloaded from
:: repository without git.
SET DEFAULT_VERSION=v1.0.0-alpha0

REM ----------
REM Variables
REM ----------
:: Strings
::   non-quoted initial value means a non-quoted end value
::   csv==comma seperated value
SET csvFILE_VERSION=
SET strFILE_VERSION=""
SET strPRIVATE=
SET strCOMMENT=
SET strSTAGE=

:: Numerics
::    Stages: 0 = alpha, 1 = beta, 2 = release candidate, 3 = release
::    Default stage is 3 (release)
SET nbSTAGE=3
SET nbSTAGE_VERSION=0
SET nbPATCHES=0

:: VS_FF_ flags
SET fPRIVATE=0
SET fPATCHED=0
SET fPRE_RELEASE=0

REM =========
REM Initialize version string.
REM =========
:: Read in packed source file version value if available.
IF EXIST %VERSION_FILE% (
  FOR /F "tokens=3" %%A IN (%VERSION_FILE%) DO (
    SET strFILE_VERSION=%%A
  )
)

REM ==========
REM Build version from git-describe
REM ==========
:: Read in git-describe output if available.
CALL git describe>NUL 2>&1
IF ERRORLEVEL 1 GOTO DEFAULT

FOR /F "tokens=*" %%A IN ('"git describe --abbrev=5 HEAD"') DO (
  SET strFILE_VERSION=%%A
)

:: When HEAD is dirty then this is not part of an official build and even if a
:: commit hasn't been made it should still be marked as dirty and patched.
SET tmp=
CALL git update-index -q --refresh >NUL 2>&1
FOR /F %%A IN ('git diff-index --name-only HEAD --') DO SET tmp=%%A
IF NOT "%tmp%" == "" (
  SET strFILE_VERSION=%strFILE_VERSION%-dirty
  SET fPRIVATE=1
  SET fPATCHED=1
)
SET tmp=

:: Exit early if a cached git built version matches the current version.
IF EXIST "%HEADER_OUT_FILE%" (
  IF [%FORCE%] EQU [1] DEL %CACHE_FILE%
  SET FORCE=0
  IF EXIST "%CACHE_FILE%" (
    FOR /F "tokens=*" %%A IN (%CACHE_FILE%) DO (
      SET strTMP_FILE_VERSION=%%A
      IF "%strTMP_FILE_VERSION%" == "%strFILE_VERSION%" (
        ECHO Build version is assumed unchanged from commit: %strFILE_VERSION%.
        GOTO :EOF
      )
    )
  )
)
ECHO %strFILE_VERSION%> %CACHE_FILE%

:: Get the number of patches/commits since the last '.0' for this stage.
ECHO %strFILE_VERSION% | FINDSTR /R ".*\-alpha" >NUL 2>&1
IF NOT ERRORLEVEL 1 (
  SET strSTAGE=-alpha0
) ELSE (
  ECHO %strFILE_VERSION% | FINDSTR /R ".*\-beta" >NUL 2>&1
  IF NOT ERRORLEVEL 1 (
    SET strSTAGE=-beta0
  ) ELSE (
    ECHO %strFILE_VERSION% | FINDSTR /R ".*\-rc" >NUL 2>&1
    IF NOT ERRORLEVEL 1 (
      SET strSTAGE=-rc0
    )
  )
)

:: Skip the Major.Minor.Fix portion of the version, then read in the description
:: of the current commit in terms of the last '.0' tag.
SET tmp=%strFILE_VERSION:~,6%%strSTAGE%
IF NOT DEFINED strSTAGE (
  FOR /F "tokens=2 delims=-" %%A IN (^
         '"git describe --match %tmp% -- 2> NUL"') DO (
    SET nbPATCHES=%%A
  )
) ELSE (
  FOR /F "tokens=3 delims=-" %%A IN (^
         '"git describe --match %tmp% -- 2> NUL"') DO (
    SET nbPATCHES=%%A
  )
)
SET tmp=

:: When the build is dirty or has patches then it is a private build.
:: To capture maint fix commits the # of patches is checked to match the fix tag
:: and HEAD needs to have been clean (so fPRIVATE is 0).
IF %nbPATCHES% GTR 0 (
  IF %nbPATCHES% EQU %strFILE_VERSION:~5,1% (
    IF %fPRIVATE% EQU 1 (
      SET fPATCHED=1
    )
  ) ELSE (
    SET fPATCHED=1
  )
)
IF %fPRIVATE% EQU 1 SET strPRIVATE=Custom Build
GOTO SETDIGIT

:DEFAULT
IF %strFILE_VERSION% == "" SET strFILE_VERSION=%DEFAULT_VERSION%

:SETDIGIT
SET csvFILE_VERSION=%strFILE_VERSION:~1,5%
SET csvFILE_VERSION=%strFILE_VERSION:.=,%

REM ----------
REM Set pre-release values.
REM ----------
ECHO %strFILE_VERSION% | FINDSTR /R ".*\-alpha" >NUL 2>&1
IF NOT ERRORLEVEL 1 GOTO SETALPHA
ECHO %strFILE_VERSION% | FINDSTR /R ".*\-beta" >NUL 2>&1
IF NOT ERRORLEVEL 1 GOTO SETBETA
ECHO %strFILE_VERSION% | FINDSTR /R ".*\-rc" >NUL 2>&1
IF NOT ERRORLEVEL 1 GOTO SETRC

GOTO WRITEVN

::  Use tmp value for stage version (ie: rc1 is 1, alpha2 is 2)
:SETALPHA
SET nbSTAGE=0
SET tmp=%strFILE_VERSION:~12%
SET strCOMMENT=Alpha Release
GOTO SETPREVAL

:SETBETA
SET nbSTAGE=1
SET tmp=%strFILE_VERSION:~11%
SET strCOMMENT=Beta Release
GOTO SETPREVAL

:SETRC
SET nbSTAGE=2
SET tmp=%strFILE_VERSION:~9%
SET strCOMMENT=Release Candidate

:SETPREVAL
SET fPRE_RELEASE=1
FOR /F "tokens=1 delims=-" %%A IN ("%tmp%") DO SET nbSTAGE_VERSION=%%A
SET strCOMMENT=%strCOMMENT% %nbSTAGE_VERSION%
IF %nbPATCHES% EQU 0 SET nbPATCHES=%nbSTAGE_VERSION%
SET tmp=

:WRITEVN
SET strFILE_VERSION=%strFILE_VERSION:~1%
SET strFILE_VERSION=%strFILE_VERSION:-=.%

SET csvFILE_VERSION=%strFILE_VERSION:~,4%%nbSTAGE%,%nbPATCHES%
SET csvFILE_VERSION=%csvFILE_VERSION:.=,%

IF NOT %fPRIVATE% EQU 0 SET fPRIVATE=VS_FF_PRIVATEBUILD
IF NOT %fPATCHED% EQU 0 SET fPATCHED=VS_FF_PATCHED
IF NOT %fPRE_RELEASE% EQU 0 SET fPRE_RELEASE=VS_FF_PRERELEASE

IF EXIST "%HEADER_OUT_FILE%" DEL "%HEADER_OUT_FILE%"
ECHO //GIT-VS-VERSION-GEN.bat generated resource header. >%HEADER_OUT_FILE%
ECHO #define GEN_VER_VERSION_STRING "%strFILE_VERSION%\0" >>%HEADER_OUT_FILE%
ECHO #define GEN_VER_DIGITAL_VERSION %csvFILE_VERSION% >>%HEADER_OUT_FILE%
ECHO #define GEN_VER_COMMENT_STRING "%strCOMMENT%\0" >>%HEADER_OUT_FILE%
ECHO #define GEN_VER_PRIVATE_FLAG %fPRIVATE% >>%HEADER_OUT_FILE%
ECHO #define GEN_VER_PRIVATE_STRING "%strPRIVATE%\0" >>%HEADER_OUT_FILE%
ECHO #define GEN_VER_PATCHED_FLAG %fPATCHED% >>%HEADER_OUT_FILE%
ECHO #define GEN_VER_PRERELEASE_FLAG %fPRE_RELEASE% >>%HEADER_OUT_FILE%

:END
ECHO Version String:: %strFILE_VERSION%
ECHO Digital Version ID: %csvFILE_VERSION%
ECHO Comment: %strCOMMENT%
ECHO Private Build String: %strPRIVATE%
ECHO Is Private Build: %fPRIVATE%
ECHO Is Patched: %fPATCHED%
ECHO Is PreRelease: %fPRE_RELEASE%

GOTO :EOF

:USAGE
ECHO usage: [--force] [CACHE_PATH] OUT_FILE
ECHO.
ECHO  --force - ignore the cached output of a previous run even if the git-describe
ECHO            version hasn't changed.
ECHO  CACHE_PATH  - Path for non-tracked file to store git-describe version.
ECHO  OUT_FILE - Path to writable file that is included in the project's rc file.
ECHO.
ECHO  Example pre-build event:
ECHO  CALL $(SolutionDir)..\scripts\GIT-VS-VERSION-GEN.bat "$(IntDir)\" "$(SolutionDir)..\src\gen-versioninfo.h"
