#!/usr/bin/env python3
"""Generate LCL resources from the maintained Delphi forms, without editing them."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "src/forms"
OUTPUT.mkdir(parents=True, exist_ok=True)

for name in ("KM_FormMain", "KM_FormLoading"):
    source = (ROOT / "src/forms" / f"{name}.dfm").read_text()
    source = source.replace(": TCategoryPanelGroup", ": TKMCategoryPanelGroup")
    source = source.replace(": TCategoryPanel", ": TKMCategoryPanel")
    source = re.sub(
        r"^\s*(?:Explicit\w+|TextHeight|Header\w+(?:\.\w+)?|"
        r"(?:Parent)?Ctl3D|(?:Parent)?DoubleBuffered|VertScrollBar\.Tracking) = .*\n",
        "", source, flags=re.MULTILINE,
    )
    target = OUTPUT / f"{name}.lfm"
    data = ("\n".join(line.rstrip() for line in source.splitlines()) + "\n").encode()
    if not target.exists() or target.read_bytes() != data:
        target.write_bytes(data)
