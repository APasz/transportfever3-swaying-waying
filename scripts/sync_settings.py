"""Generate or verify mod UI settings from the compiled typed definitions."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--generate", action="store_true")
    mode.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    expected: object = json.loads(
        subprocess.check_output(["lua", "scripts/export_settings.lua"], cwd=root, text=True)
    )
    manifest_path = root / "mod.json"
    manifest = json.loads(manifest_path.read_text())
    if manifest["params"] == expected:
        return
    if not args.generate:
        raise SystemExit("Stale mod settings: run scripts/validate.sh --generate")
    manifest["params"] = expected
    manifest_path.write_text(json.dumps(manifest, indent=4, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
