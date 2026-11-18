#!/usr/bin/env python3
"""Archive the stock browser runtime for P42-01 without publishing it."""

import argparse
import json
from pathlib import Path

if __package__:
    from .check_version import manifest_version
    from .release_archive import ROOT, validate_version, write_archive
else:
    from check_version import manifest_version
    from release_archive import ROOT, validate_version, write_archive


WASM_HEADER = b"\x00asm\x01\x00\x00\x00"
README = """# BeSpoke Engine {version}: browser runtime

`bespoke.wasm` is the freestanding engine module. It needs no Zig, SDL2,
or WebAssembly imports to run. Serve this directory over HTTP if your
browser host fetches the module. Verify files with `sha256sum -c SHA256SUMS`.

From JavaScript in a page served alongside the module:

```js
const response = await fetch("./bespoke.wasm");
if (!response.ok) throw new Error("Could not load bespoke.wasm");
const {{ instance }} = await WebAssembly.instantiate(await response.arrayBuffer());
const engine = instance.exports;
engine.wasm_init(0);
engine.wasm_step_tick();
engine.wasm_render_frame();
// Read RGBA pixels from engine.memory.buffer, starting at
// engine.wasm_framebuffer_ptr(), for engine.wasm_framebuffer_len() bytes.
```

Deck 0 is the neutral stage; deck 1 runs a built-in BeSpoke script. The
module contains these fixed decks and does not include a browser page or
load arbitrary scripts from a URL. For your own game, use the project's
`bespoke init` and `zig build web` workflow to generate a matching HTML
host and Wasm module with your script embedded.
"""


def package_browser(output_dir: Path, version: str, wasm: bytes, license_bytes: bytes, limit: int) -> Path:
    validate_version(version)
    if len(wasm) <= len(WASM_HEADER) or not wasm.startswith(WASM_HEADER):
        raise ValueError("expected a nonempty WebAssembly version 1 module")
    if len(wasm) > limit:
        raise ValueError(f"bespoke.wasm exceeds the {limit}-byte budget")
    name = f"bespoke-browser-{version}"
    return write_archive(output_dir, name, {
        "README.md": README.format(version=version).encode(),
        "LICENSE": license_bytes,
        "bespoke.wasm": wasm,
    })


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=ROOT / "dist" / "release")
    args = parser.parse_args()
    try:
        budget_text = Path(__file__).with_name("web_budgets.json").read_text(encoding="utf-8")
        path = package_browser(
            args.output_dir,
            manifest_version(ROOT / "build.zig.zon"),
            (ROOT / "zig-out" / "bin" / "bespoke.wasm").read_bytes(),
            (ROOT / "LICENSE").read_bytes(),
            json.loads(budget_text)["wasmModuleBytes"],
        )
    except (OSError, ValueError) as exc:
        parser.exit(1, f"{exc}\n")
    print(path)


if __name__ == "__main__":
    main()
