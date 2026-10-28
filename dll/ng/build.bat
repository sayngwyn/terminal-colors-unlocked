@echo off
rem Next-gen 1.11.240 DLL. Output: build\windows\x64\releasedbg\TerminalColorsUnlocked.dll
rem Needs VS 2022 Build Tools and xmake plus libxse/commonlibf4 in a
rem shared\tools folder beside this repo (or set COMMONLIBF4_NG).
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat" -arch=amd64 -host_arch=amd64 >nul
set TOOLS=%~dp0..\..\..\shared\tools
set PATH=%TOOLS%\xmake;%PATH%
set XMAKE_GLOBALDIR=%TOOLS%\xmake-cache
if not defined COMMONLIBF4_NG set COMMONLIBF4_NG=%TOOLS%\f4se-cpp\template\lib\commonlibf4
rem Strip this machine's folders from file names compiled into the DLL
rem (__FILE__ / source_location). Passed through cl's CL variable because
rem xmake can't keep a flag with a space in it as one argument.
for %%I in ("%~dp0..\..\..") do set CL=/d1trimfile:"%%~fI\\"
cd /d "%~dp0"
xmake f -c -p windows -a x64 -m releasedbg -y || exit /b 1
xmake -y || exit /b 1
