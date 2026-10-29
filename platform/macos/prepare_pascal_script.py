#!/usr/bin/env python3
"""Apply the native FPC patches to a build copy of the pinned PascalScript source."""
from pathlib import Path
import hashlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "src/ext/pascalscript_submodule"
DESTINATION = ROOT / "assets.local/toolchain/pascalscript"
REVISION = "ce8590dd7b9cf48fd0e446731989603e09e239b8"
PATCHES = sorted((ROOT / "platform/macos/patches").glob("pascalscript-*.patch"))

revision = subprocess.check_output(["git", "-C", str(SOURCE), "rev-parse", "HEAD"], text=True).strip()
if revision != REVISION:
    raise SystemExit("Initialize the pinned PascalScript submodule before building macOS")

digest = hashlib.sha256()
for path in sorted((SOURCE / "Source").rglob("*")) + PATCHES:
    if path.is_file():
        digest.update(path.name.encode())
        digest.update(path.read_bytes())
signature = digest.hexdigest()
marker = DESTINATION / "source.sha256"
if marker.exists() and marker.read_text().strip() == signature:
    raise SystemExit(0)

if DESTINATION.exists():
    shutil.rmtree(DESTINATION)
shutil.copytree(SOURCE / "Source", DESTINATION / "Source")
for path in (DESTINATION / "Source").rglob("*"):
    if path.suffix.lower() in (".pas", ".pp", ".inc"):
        path.write_bytes(path.read_bytes().replace(b"\r\n", b"\n"))
for patch in PATCHES:
    subprocess.run(["patch", "--batch", "-p1", "-i", str(patch)], cwd=DESTINATION, check=True)
marker.write_text(signature + "\n")
