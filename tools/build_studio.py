#!/usr/bin/env python3
"""Build site/studio.html, BeSpoke Studio (P47-01, D-192), from studio/.

    zig build studio && python3 tools/build_studio.py           # write the page
    python3 tools/build_studio.py --check                       # fail if the page is stale

The page is one file: studio/page.html with the engine's 5x7 font table (read out of the
Studio's wasm module by studio/font_table.js, so src/display/font.zig stays its one source),
the version from build.zig.zon, the Studio and play wasm modules as base64 (D-195), and the
five scripts, inlined at their markers. Nothing else in the repository is read or changed.
"""

import argparse
import base64
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STUDIO = ROOT / "studio"
STUDIO_PATH = ROOT / "site" / "studio.html"
WASM_ARTIFACT = ROOT / "zig-out" / "bin" / "bespoke-studio.wasm"
PLAY_ARTIFACT = ROOT / "zig-out" / "bin" / "bespoke-play.wasm"
MARKERS = ("<!--@FONT-->", "<!--@BUILD-->", "<!--@WINDOWS-->", "<!--@PLAY-->", "<!--@PAINT-->", "<!--@ROOM-->", "<!--@APP-->")


def version() -> str:
    text = (ROOT / "build.zig.zon").read_text(encoding="utf-8")
    match = re.search(r'\.version\s*=\s*"([^"]+)"', text)
    if not match:
        raise SystemExit("build.zig.zon has no .version")
    return match.group(1)


def script(body: str) -> str:
    # An inlined script ends at the first "</script"; the sources never need one, so refuse
    # rather than escape, which would change what the browser runs.
    if "</script" in body.lower():
        raise SystemExit("an inlined Studio script contains </script")
    return f"<script>\n{body.rstrip()}\n</script>"


def render(wasm: bytes, play: bytes, font: dict) -> str:
    page = (STUDIO / "page.html").read_text(encoding="utf-8")
    for marker in MARKERS:
        if page.count(marker) != 1:
            raise SystemExit(f"studio/page.html must contain {marker} exactly once")
    build = {
        "version": version(),
        "wasm": base64.b64encode(wasm).decode("ascii"),
        "play": base64.b64encode(play).decode("ascii"),
    }
    parts = {
        "<!--@FONT-->": script("const STUDIO_FONT = " + json.dumps(font, separators=(",", ":"), sort_keys=True) + ";"),
        "<!--@BUILD-->": script("const STUDIO_BUILD = " + json.dumps(build, separators=(",", ":")) + ";"),
        "<!--@WINDOWS-->": script((STUDIO / "windows.js").read_text(encoding="utf-8")),
        "<!--@PLAY-->": script((STUDIO / "play.js").read_text(encoding="utf-8")),
        "<!--@PAINT-->": script((STUDIO / "paint.js").read_text(encoding="utf-8")),
        "<!--@ROOM-->": script((STUDIO / "room.js").read_text(encoding="utf-8")),
        "<!--@APP-->": script((STUDIO / "studio.js").read_text(encoding="utf-8")),
    }
    for marker, body in parts.items():
        page = page.replace(marker, body)
    return page


def font_table(wasm_path: Path) -> dict:
    out = subprocess.run(["node", str(STUDIO / "font_table.js"), str(wasm_path)], check=True, capture_output=True, text=True)
    return json.loads(out.stdout)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="fail when site/studio.html differs from a fresh build")
    parser.add_argument("--wasm", type=Path, default=WASM_ARTIFACT, help="bespoke-studio.wasm to embed")
    parser.add_argument("--play", type=Path, default=PLAY_ARTIFACT, help="bespoke-play.wasm to embed (P47-06, D-195)")
    args = parser.parse_args()
    try:
        wasm = args.wasm.read_bytes()
    except OSError as exc:
        raise SystemExit(f"Studio module not found at {args.wasm}; run `zig build studio` first") from exc
    try:
        play = args.play.read_bytes()
    except OSError as exc:
        raise SystemExit(f"play module not found at {args.play}; run `zig build studio` first") from exc
    page = render(wasm, play, font_table(args.wasm))
    if args.check:
        current = STUDIO_PATH.read_text(encoding="utf-8") if STUDIO_PATH.exists() else None
        if current != page:
            print(f"{STUDIO_PATH.relative_to(ROOT)} is stale; run `zig build studio && python3 tools/build_studio.py`", file=sys.stderr)
            return 1
        print(f"{STUDIO_PATH.relative_to(ROOT)} is current ({len(page.encode('utf-8'))} bytes)")
        return 0
    STUDIO_PATH.write_text(page, encoding="utf-8")
    print(f"wrote {STUDIO_PATH.relative_to(ROOT)} ({len(page.encode('utf-8'))} bytes, wasm {len(wasm)} + {len(play)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
