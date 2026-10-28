@echo off
rem Old-gen DLL (1.10.163 + 1.10.984). Output: build\TerminalColorsUnlocked.dll
rem Needs VS 2022 Build Tools (MSVC 14.44) and alandtse/CommonLibF4 + vcpkg
rem in shared\tools\f4se-cpp\og beside this repo.
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat" -arch=amd64 -host_arch=amd64 -vcvars_ver=14.44 >nul
set OG=%~dp0..\..\..\shared\tools\f4se-cpp\og
set VCPKG_ROOT=%OG%\vcpkg
set VCPKG_INSTALLATION_ROOT=%OG%\vcpkg
set VCPKG_DEFAULT_BINARY_CACHE=%OG%\cache\binary
set VCPKG_DOWNLOADS=%OG%\cache\downloads
set X_VCPKG_REGISTRIES_CACHE=%OG%\cache\registries
set VCPKG_DISABLE_METRICS=1
cd /d "%~dp0"
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release ^
 -DCOMMONLIBF4_DIR="%OG%\CommonLibF4\CommonLibF4" ^
 -DCMAKE_TOOLCHAIN_FILE="%VCPKG_ROOT%\scripts\buildsystems\vcpkg.cmake" ^
 -DVCPKG_TARGET_TRIPLET=x64-windows-static-md -DVCPKG_HOST_TRIPLET=x64-windows-static-md ^
 -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL -DCMAKE_CXX_COMPILER=cl ^
 -DCMAKE_CXX_FLAGS="/DWIN32_LEAN_AND_MEAN /DNOMINMAX /DUNICODE /D_UNICODE /permissive- /Zc:preprocessor /EHsc /MP /bigobj /utf-8" || exit /b 1
cmake --build build || exit /b 1
