# Builds the FOMOD release zip in dist\release (git-ignored), holding both
# DLLs. Build the DLLs first (dll\og\build.bat, dll\ng\build.bat).
# Usage: powershell -File tools\build_release.ps1
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent

# Scripts compiled against F4SE 0.6.23 run on 0.7.x too.
& (Join-Path $PSScriptRoot 'build.ps1') -F4SE 0.6.23 | Out-Null

$version = ([xml](Get-Content (Join-Path $repo 'src\fomod\info.xml') -Raw)).fomod.Version
$outDir = Join-Path $repo 'dist\release'
New-Item -ItemType Directory -Force $outDir | Out-Null
$zip = Join-Path $outDir "Terminal Colors Unlocked $version.zip"
python -I (Join-Path $PSScriptRoot 'make_release.py') $repo (Join-Path $repo 'dist\package') $zip
if ($LASTEXITCODE -ne 0) { throw "Release zip failed" }
