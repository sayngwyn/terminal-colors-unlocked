-- Next-gen / AE (1.11.240) DLL, libxse commonlibf4. Built by build.bat.
-- COMMONLIBF4_NG points at a libxse/commonlibf4 checkout.
includes(os.getenv("COMMONLIBF4_NG") or "lib/commonlibf4")

set_project("TerminalColorsUnlocked")
set_version("1.0.0")
set_license("GPL-3.0")
set_languages("c++23")
set_warnings("allextra")

add_rules("mode.debug", "mode.releasedbg")

-- Self-test build only (build.bat test): never in a release.
option("selftest", function()
    set_default(false)
    add_defines("TCU_SELFTEST")
end)

target("TerminalColorsUnlocked")
    add_rules("commonlibf4.plugin", {
        name = "TerminalColorsUnlocked",
        author = "sayngwyn",
        description = "Terminal Colors Unlocked: ini reads for its scripts and the terminal screen tint"
    })

    add_options("selftest")
    add_files("src/**.cpp")
    add_headerfiles("src/**.h", "../src/**.h")
    add_includedirs("src", "../src")
    set_pcxxheader("src/pch.h")
    -- Record only the .pdb's file name in the DLL, not the build folder.
    add_shflags("/PDBALTPATH:%_PDB%", {force = true})
