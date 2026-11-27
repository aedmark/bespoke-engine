#!/usr/bin/env python3
"""Check raw byte budgets for BeSpoke's browser artifacts (P41-01)."""

import argparse
import json
from pathlib import Path
import sys

if __package__:
    from .build_site import HARBOUR_PATH, HTML_PATH, PROOF_PAGE_PATHS, ROOT
else:
    from build_site import HARBOUR_PATH, HTML_PATH, PROOF_PAGE_PATHS, ROOT


def check_sizes(entries: list[tuple[Path, int]]) -> bool:
    ok = True
    for path, limit in entries:
        try:
            if not path.is_file():
                raise FileNotFoundError(path)
            size = path.stat().st_size
        except OSError:
            print(f"FAIL {path}: missing or unreadable", file=sys.stderr)
            ok = False
            continue
        status = "ok  " if size <= limit else "FAIL"
        print(f"{status} {path}: {size:,} / {limit:,} bytes")
        ok &= size <= limit
    return ok


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lantern-page", type=Path, help="also check a freshly built Lantern Watch export")
    parser.add_argument("--sunken-vault-page", type=Path, help="also check a freshly built Sunken Vault export")
    args = parser.parse_args()
    budgets = json.loads(Path(__file__).with_name("web_budgets.json").read_text(encoding="utf-8"))
    modules = [ROOT / "zig-out" / "bin" / name for name in ("bespoke.wasm", "bespoke-proofs.wasm")]
    entries = [(p, budgets["wasmModuleBytes"]) for p in modules]
    entries.append((HTML_PATH, budgets["showcasePageBytes"]))
    entries.append((HARBOUR_PATH, budgets["standalonePageBytes"]))
    entries.extend((p, budgets["standalonePageBytes"]) for p in PROOF_PAGE_PATHS)
    if args.lantern_page is not None:
        entries.append((args.lantern_page, budgets["standalonePageBytes"]))
    if args.sunken_vault_page is not None:
        entries.append((args.sunken_vault_page, budgets["standalonePageBytes"]))
    return 0 if check_sizes(entries) else 1


if __name__ == "__main__":
    raise SystemExit(main())
