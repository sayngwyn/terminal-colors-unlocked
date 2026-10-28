"""Assemble the FOMOD release zip from a built package and both DLLs.

Layout: fomod/, "00 Core" (plugin, archive, MCM), "10 Old-gen" and
"20 Next-gen" (F4SE/Plugins/TerminalColorsUnlocked.dll each). Entries are
sorted with a fixed timestamp, so the same inputs give the same zip.
Usage: python make_release.py <repo> <package dir> <out.zip>
"""
import re
import sys
import zipfile
from pathlib import Path

DLL = Path('F4SE/Plugins/TerminalColorsUnlocked.dll')
STAMP = (2026, 1, 1, 0, 0, 0)


def main(repo, package, out):
    repo, package = Path(repo), Path(package)
    found = re.search(r'<Version>(.+?)</Version>', (repo / 'src/fomod/info.xml').read_text('utf-8'))
    if not found:
        sys.exit('no <Version> in src/fomod/info.xml')
    version = found.group(1)
    entries = {}
    for f in (repo / 'src/fomod').iterdir():
        entries[f'fomod/{f.name}'] = f
    for f in package.rglob('*'):
        rel = f.relative_to(package)
        if f.is_file() and rel.parts[0] != 'F4SE':
            entries[f'00 Core/{rel.as_posix()}'] = f
    entries[f'10 Old-gen/{DLL.as_posix()}'] = repo / 'dll/og/build/TerminalColorsUnlocked.dll'
    entries[f'20 Next-gen/{DLL.as_posix()}'] = repo / 'dll/ng/build/windows/x64/releasedbg/TerminalColorsUnlocked.dll'
    for name, src in entries.items():
        if not src.is_file():
            sys.exit(f'missing: {src} (for {name})')
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for name in sorted(entries):
            info = zipfile.ZipInfo(name, STAMP)
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, entries[name].read_bytes())
    print(f'{out}: version {version}, {len(entries)} files')


if __name__ == '__main__':
    main(*sys.argv[1:4])
