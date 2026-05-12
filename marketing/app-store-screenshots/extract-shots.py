#!/usr/bin/env python3
"""Extract named XCTAttachment screenshots from an xcresult bundle.

The UI test attaches each capture with a stable name like "01-home" so this
script can rename the GUID-named exports back into <name>.png files under the
target device's raw/ directory.

Usage:
    extract-shots.py <xcresult-path> <output-dir>
"""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


NAME_RE = re.compile(r"(\d{2}-[a-z]+)_\d+_")


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2

    xcresult = Path(sys.argv[1])
    out_dir = Path(sys.argv[2])
    if not xcresult.exists():
        print(f"error: {xcresult} not found", file=sys.stderr)
        return 1
    out_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        subprocess.run(
            [
                "xcrun",
                "xcresulttool",
                "export",
                "attachments",
                "--path",
                str(xcresult),
                "--output-path",
                str(tmp_path),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        manifest = json.loads((tmp_path / "manifest.json").read_text())
        saved = 0
        for run in manifest:
            for att in run.get("attachments", []):
                name = att.get("suggestedHumanReadableName", "")
                match = NAME_RE.match(name)
                if not match:
                    continue
                src = tmp_path / att["exportedFileName"]
                dst = out_dir / f"{match.group(1)}.png"
                shutil.copy(src, dst)
                print(f"saved {dst.name}")
                saved += 1

    print(f"\nExtracted {saved} screenshot(s) to {out_dir}")
    return 0 if saved else 1


if __name__ == "__main__":
    sys.exit(main())
