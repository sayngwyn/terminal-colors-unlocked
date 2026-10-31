@echo off
rem Next-gen 1.11.240 DLL. Output: build\windows\x64\releasedbg\TerminalColorsUnlocked.dll
rem "build.bat test" builds the self-test DLL into bt\ (never ship it).
rem Needs VS 2022 Build Tools and xmake plus libxse/commonlibf4 in a
rem shared\tools folder beside this repo (or set TCU_SHARED to that shared
rem folder, e.g. when building from a git worktree, or COMMONLIBF4_NG).
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat" -arch=amd64 -host_arch=amd64 >nul
if not defined TCU_SHARED set TCU_SHARED=%~dp0..\..\..\shared
set TOOLS=%TCU_SHARED%\tools
set PATH=%TOOLS%\xmake;%PATH%
set XMAKE_GLOBALDIR=%TOOLS%\xmake-cache
if not defined COMMONLIBF4_NG set COMMONLIBF4_NG=%TOOLS%\f4se-cpp\template\lib\commonlibf4
rem Strip this machine's folders from file names compiled into the DLL
rem (__FILE__ / source_location). Passed through cl's CL variable because
rem xmake can't keep a flag with a space in it as one argument.
for %%I in ("%~dp0..\..\..") do set CL=/d1trimfile:"%%~fI\\"
set OUT=build
set SELFTEST=n
rem The test folder name is short: xmake's PCH paths for the shared library
rem pass Windows' 260-character limit in a deep (worktree) folder otherwise.
if /i "%~1"=="test" (set OUT=bt& set SELFTEST=y)
cd /d "%~dp0"
xmake f -c -p windows -a x64 -m releasedbg --selftest=%SELFTEST% -o %OUT% -y || exit /b 1
xmake -y || exit /b 1
