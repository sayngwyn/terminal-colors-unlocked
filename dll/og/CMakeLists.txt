cmake_minimum_required(VERSION 3.21)
project(TerminalColorsUnlocked VERSION 1.0.0 LANGUAGES CXX)

if("${PROJECT_SOURCE_DIR}" STREQUAL "${PROJECT_BINARY_DIR}")
	message(FATAL_ERROR "in-source builds are not allowed")
endif()

# Old-gen DLL: Fallout 4 1.10.163 and 1.10.984 in one, alandtse/CommonLibF4.
set(ENABLE_FALLOUT_F4 ON CACHE BOOL "" FORCE)
set(ENABLE_FALLOUT_NG ON CACHE BOOL "" FORCE)
set(ENABLE_FALLOUT_VR OFF CACHE BOOL "" FORCE)
set(F4SE_SUPPORT_XBYAK OFF CACHE BOOL "" FORCE)
set(BUILD_TESTS OFF CACHE BOOL "" FORCE)

# Strip the build machine's folders from file names compiled into the DLL
# (__FILE__ / source_location), here and in the library.
get_filename_component(TCU_TRIM_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)
file(TO_NATIVE_PATH "${TCU_TRIM_ROOT}/" TCU_TRIM_ROOT)
add_compile_options("/d1trimfile:${TCU_TRIM_ROOT}")

set(COMMONLIBF4_DIR "" CACHE PATH "alandtse/CommonLibF4's CommonLibF4 folder")
add_subdirectory("${COMMONLIBF4_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/CommonLibF4")

add_library(TerminalColorsUnlocked SHARED src/main.cpp src/pch.h ../src/Natives.h ../src/WorldTint.h ../src/SelfTest.h)
# Self-test build only (build.bat test): never in a release.
option(TCU_SELFTEST "Build the in-game self-test" OFF)
if(TCU_SELFTEST)
	target_compile_definitions(TerminalColorsUnlocked PRIVATE TCU_SELFTEST)
endif()
set_target_properties(TerminalColorsUnlocked PROPERTIES CXX_STANDARD 23 CXX_STANDARD_REQUIRED ON)
target_compile_definitions(TerminalColorsUnlocked PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE)
target_include_directories(TerminalColorsUnlocked PRIVATE src ../src)
target_link_libraries(TerminalColorsUnlocked PRIVATE CommonLibF4::CommonLibF4)
target_precompile_headers(TerminalColorsUnlocked PRIVATE src/pch.h)
if(MSVC)
	target_compile_options(TerminalColorsUnlocked PRIVATE /permissive- /Zc:preprocessor /EHsc /utf-8 /bigobj /W4 /external:anglebrackets /external:W0)
endif()
