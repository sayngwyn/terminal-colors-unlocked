#pragma once

#include <RE/Fallout.h>
#include <F4SE/F4SE.h>

using namespace std::literals;

// Shims for the code shared with the next-gen DLL (dll\src).
#define TCU_LOG(...) F4SE::log::info(__VA_ARGS__)
#define TCU_NODE_CHILDREN(node) (node)->GetRuntimeData().children
