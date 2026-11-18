#!/usr/bin/env python3
"""Pack a generated game's browser build into one static HTML file."""

import argparse
import base64
from html import escape
from pathlib import Path
import re


LOADER = re.compile(r"WebAssembly\.instantiateStreaming\(fetch\('([a-z][a-z0-9_]{0,31}\.wasm)'\), \{\}\)")
LICENSE = Path(__file__).resolve().parents[1] / "LICENSE"


def pack(web_dir: Path) -> str:
    html = (web_dir / "index.html").read_text(encoding="utf-8")
    matches = list(LOADER.finditer(html))
    if len(matches) != 1:
        raise ValueError("expected exactly one generated BeSpoke WebAssembly loader in index.html")
    match = matches[0]
    wasm = (web_dir / match[1]).read_bytes()
    if not wasm.startswith(b"\x00asm\x01\x00\x00\x00"):
        raise ValueError(f"{match[1]} is not a WebAssembly module")
    payload = base64.b64encode(wasm).decode("ascii")
    loader = f"WebAssembly.instantiate(Uint8Array.from(atob('{payload}'), c => c.charCodeAt(0)), {{}})"
    page = html[:match.start()] + loader + html[match.end():]
    body, closing, rest = page.rpartition("</body>")
    if not closing:
        raise ValueError("generated index.html is missing its closing body tag")
    license_text = escape(LICENSE.read_text(encoding="utf-8"))
    return f'{body}<template id="bespoke-license"><pre>{license_text}</pre></template>\n{closing}{rest}'


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("web_dir", type=Path, help="browser build directory, usually zig-out/web")
    parser.add_argument("output", type=Path, help="new .html file to write")
    args = parser.parse_args()
    if args.output.suffix != ".html":
        parser.error("output must end in .html")
    try:
        page = pack(args.web_dir)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("x", encoding="utf-8") as out:
            out.write(page)
    except FileExistsError:
        parser.exit(1, f"refusing to overwrite {args.output}; choose a new output path\n")
    except (OSError, ValueError) as err:
        parser.exit(1, f"could not pack game page: {err}\n")
    print(f"Upload {args.output}")


if __name__ == "__main__":
    main()
