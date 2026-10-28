# Builds the mod into dist\package (git-ignored): plugin, "<plugin> - Main.ba2"
# (scripts + terminal tint) and the loose MCM folder (MCM reads it from disk).
# Usage: powershell -File tools\build.ps1 [-F4SE 0.6.23|0.7.9]
param([string]$F4SE = '0.6.23')
$ErrorActionPreference = 'Stop'

$repo  = Split-Path $PSScriptRoot -Parent
# Papyrus compiler, F4SE and vanilla script sources, FFDec: TCU_TOOLS, or a
# shared\tools folder beside this repo.
$tools = if ($env:TCU_TOOLS) { $env:TCU_TOOLS } else { Join-Path (Split-Path $repo -Parent) 'shared\tools' }
$out   = Join-Path $repo 'dist\build'
$work  = Join-Path $repo 'dist\work'
New-Item -ItemType Directory -Force "$out\Scripts", $work | Out-Null

# Papyrus
$src  = Join-Path $repo 'src\Scripts\Source\User'
$base = "$tools\papyrus\source\vanilla\Base"
& "$tools\papyrus\compiler\PapyrusCompiler.exe" $src -all -quiet `
    "-f=$base\Institute_Papyrus_Flags.flg" `
    "-i=$src;$tools\papyrus\source\f4se-$F4SE;$base" "-o=$out\Scripts"
if ($LASTEXITCODE -ne 0) { throw "Papyrus compile failed" }
# The compiler stamps the source path, user and computer name into each .pex.
python -I (Join-Path $PSScriptRoot 'scrub_pex.py') "$out\Scripts" 'sayngwyn' | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Script scrub failed" }

# A SWF: an empty skeleton with a stub class, then FFDec swaps in the real class.
function Build-Swf([string]$class, [string]$source, [string]$dest) {
    $dir  = Join-Path $work $class
    New-Item -ItemType Directory -Force "$dir\as\scripts", (Split-Path $dest) | Out-Null
    $skel = Join-Path $dir 'skeleton.swf'
    python -I (Join-Path $PSScriptRoot 'make_swf_skeleton.py') $skel $class
    if ($LASTEXITCODE -ne 0) { throw "$class skeleton failed" }
    Copy-Item $source "$dir\as\scripts\$class.as" -Force
    & "$tools\ffdec\ffdec-cli.exe" -importScript $skel $dest "$dir\as" | Out-Null
    if (-not (Test-Path $dest) -or (Get-Item $dest).Length -le (Get-Item $skel).Length) { throw "$class import failed" }
}
Build-Swf 'Tint' (Join-Path $repo 'src\Interface\TerminalColorsUnlocked\Tint.as') "$out\Interface\TerminalColorsUnlocked\Tint.swf"
Build-Swf 'TCUSwatch' (Join-Path $repo 'src\MCM\TCUSwatch.as') "$out\MCM\Config\TerminalColorsUnlocked\lib.swf"

# Plugin
python -I (Join-Path $PSScriptRoot 'make_plugin.py') "$out\TerminalColorsUnlocked.esp"
if ($LASTEXITCODE -ne 0) { throw "Plugin build failed" }

# Package
$pkg = Join-Path $repo 'dist\package'
$mcm = "$pkg\MCM\Config\TerminalColorsUnlocked"
New-Item -ItemType Directory -Force $mcm | Out-Null
Copy-Item "$out\TerminalColorsUnlocked.esp" $pkg -Force
python -I (Join-Path $PSScriptRoot 'make_ba2.py') "$pkg\TerminalColorsUnlocked - Main.ba2" $out `
    'Scripts\TerminalColorsUnlocked\Main.pex' 'Scripts\TerminalColorsUnlocked\Holotape.pex' `
    'Scripts\TerminalColorsUnlockedNative.pex' `
    'Interface\TerminalColorsUnlocked\Tint.swf'
if ($LASTEXITCODE -ne 0) { throw "Archive build failed" }
# DLL for the game generation this build targets (built by dll\og or dll\ng\build.bat).
$dll = if ($F4SE -like '0.6.*') { 'dll\og\build\TerminalColorsUnlocked.dll' } `
       else { 'dll\ng\build\windows\x64\releasedbg\TerminalColorsUnlocked.dll' }
$dll = Join-Path $repo $dll
if (-not (Test-Path $dll)) { throw "DLL missing: $dll (run its build.bat)" }
New-Item -ItemType Directory -Force "$pkg\F4SE\Plugins" | Out-Null
Copy-Item $dll "$pkg\F4SE\Plugins" -Force
Copy-Item (Join-Path $repo 'src\MCM\Config\TerminalColorsUnlocked\config.json') $mcm -Force
Copy-Item "$out\MCM\Config\TerminalColorsUnlocked\lib.swf" $mcm -Force

Get-ChildItem $pkg -Recurse -File | Select-Object FullName, Length
