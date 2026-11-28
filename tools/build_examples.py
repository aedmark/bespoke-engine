#!/usr/bin/env python3
"""The demo games BeSpoke Studio opens as examples (P50-02, P50-03, D-213).

    python3 tools/build_examples.py --snapshots   # redraw proofs/scripts/art/ from the proof themes
    python3 tools/build_examples.py --check       # every example compiles with zig-out/bin/bespoke

`studio/examples.json` names each demo and its files. A proof whose art is drawn by Zig code gets
its scenes' backdrops as PNGs: `--snapshots` runs the render harness with `-Dsnapshot-backdrops`,
which draws each scene's backdrop alone, and writes one indexed 320x180 PNG per scene the
proof's script declares into `proofs/scripts/art/<proof>/`. Those PNGs are committed, so a
Studio build reads them without Zig. `bundle()` gives `tools/build_studio.py` the examples, each
script with an `image ... from` line and a `backdrop:` line added for every snapshot.
"""

import argparse
import base64
import fnmatch
import gzip
import json
import re
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "studio" / "examples.json"
SNAPSHOTS = ROOT / "proofs" / "scripts" / "art"
ART_W, ART_H = 320, 180
SCENE = re.compile(r'^scene\s*:?\s*"?([^":]+?)"?\s*:?\s*$')


def manifest() -> list[dict]:
    return json.loads(MANIFEST.read_text(encoding="utf-8"))["examples"]


def scenes(script: str) -> list[tuple[int, str]]:
    """(line index, scene name) for each `scene` header, in either form."""
    out = []
    for i, line in enumerate(script.split("\n")):
        m = SCENE.match(line)
        if m and not line.startswith(" "):
            out.append((i, m.group(1).strip()))
    return out


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def image_name(name: str) -> str:
    words = re.findall(r"[A-Za-z0-9]+", name)
    return "".join(w[:1].upper() + w[1:] for w in words) + "Backdrop"


def png(rgba: bytes, w: int, h: int) -> bytes:
    """An indexed PNG when the picture has at most 256 colours, else RGB."""
    def chunk(tag: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)
    colours: dict[bytes, int] = {}
    for i in range(0, len(rgba), 4):
        colours.setdefault(rgba[i:i + 3], len(colours))
    head = b"\x89PNG\r\n\x1a\n"
    if len(colours) <= 256:
        rows = bytearray()
        for y in range(h):
            rows.append(0)
            for x in range(w):
                i = (y * w + x) * 4
                rows.append(colours[rgba[i:i + 3]])
        return head + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 3, 0, 0, 0)) + chunk(b"PLTE", b"".join(colours)) + chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b"")
    rows = bytearray()
    for y in range(h):
        rows.append(0)
        for x in range(w):
            i = (y * w + x) * 4
            rows += rgba[i:i + 3]
    return head + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b"")


def snapshot() -> list[Path]:
    """Redraws every snapshot PNG from the proof themes."""
    written = []
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["zig", "build", "test-proofs", f"-Dsnapshot-backdrops={tmp}"], cwd=ROOT, check=True)
        raw = {p.stem: p.read_bytes() for p in Path(tmp).glob("*.rgba")}
        for ex in manifest():
            proof = ex.get("snapshots")
            if not proof:
                continue
            script = (ROOT / ex["root"] / ex["main"]).read_text(encoding="utf-8")
            out_dir = SNAPSHOTS / proof
            out_dir.mkdir(parents=True, exist_ok=True)
            for old in out_dir.glob("*.png"):
                old.unlink()
            for _, name in scenes(script):
                rgba = raw.get(f"{proof}__{name}")
                if rgba is None or len(rgba) != ART_W * ART_H * 4:
                    continue
                path = out_dir / f"{slug(name)}.png"
                path.write_bytes(png(rgba, ART_W, ART_H))
                written.append(path)
    return written


def with_backdrops(script: str, proof: str) -> tuple[str, list[tuple[str, bytes]]]:
    """The script with a backdrop line for each scene that has a snapshot, and the PNGs."""
    lines = script.split("\n")
    images = []
    art = []
    for index, name in reversed(scenes(script)):
        path = SNAPSHOTS / proof / f"{slug(name)}.png"
        if not path.exists():
            continue
        # The scene's own lines: up to the next blank line or top-level line.
        block = []
        for l in lines[index + 1:]:
            if not l.strip() or SCENE.match(l):
                break
            block.append(l)
        if any(l.strip().startswith("backdrop") for l in block):
            continue
        # A `scene Name:` block indents its lines; the flat `scene: Name` form does not.
        nxt = next((l for l in block if l.strip()), "")
        indent = nxt[: len(nxt) - len(nxt.lstrip())] if lines[index].rstrip().endswith(":") else ""
        img = image_name(name)
        lines.insert(index + 1, f"{indent}backdrop: {img}")
        images.append(f'image {img} from "art/{path.name}"')
        art.append((f"art/{path.name}", path.read_bytes()))
    text = "\n".join(lines).rstrip("\n") + "\n"
    if images:
        text += "\n# Backdrops drawn from the proof's code-drawn theme (P50-02): paint over them.\n" + "\n".join(reversed(images)) + "\n"
    return text, list(reversed(art))


def files_of(ex: dict) -> list[tuple[str, bytes]]:
    root = ROOT / ex["root"]
    out = []
    for pattern in ex["files"]:
        matches = sorted(p for p in root.rglob("*") if p.is_file() and fnmatch.fnmatch(p.relative_to(root).as_posix(), pattern))
        if not matches:
            raise SystemExit(f"studio/examples.json: {ex['id']} names {pattern}, which matches nothing under {ex['root']}")
        out.extend((p.relative_to(root).as_posix(), p.read_bytes()) for p in matches)
    return out


def example_files(ex: dict) -> list[tuple[str, bytes]]:
    files = files_of(ex)
    if ex.get("snapshots"):
        files = [(p, b) for p, b in files if p != ex["main"]]
        text, art = with_backdrops((ROOT / ex["root"] / ex["main"]).read_text(encoding="utf-8"), ex["snapshots"])
        files = [(ex["main"], text.encode("utf-8"))] + art + files
    return files


def bundle() -> str:
    """The examples as gzip-compressed JSON in base64, for the Studio page."""
    items = []
    for ex in manifest():
        files = []
        for path, data in example_files(ex):
            if path.endswith(".bespoke"):
                files.append({"path": path, "text": data.decode("utf-8")})
            else:
                files.append({"path": path, "b64": base64.b64encode(data).decode("ascii")})
        items.append({"id": ex["id"], "title": ex["title"], "main": ex["main"], "host": ex["host"], "files": files})
    raw = json.dumps(items, separators=(",", ":"), sort_keys=True).encode("utf-8")
    return base64.b64encode(gzip.compress(raw, compresslevel=9, mtime=0)).decode("ascii")


def check(cli: Path) -> int:
    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        for ex in manifest():
            folder = Path(tmp) / ex["id"]
            for path, data in example_files(ex):
                target = folder / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
            run = subprocess.run([str(cli), "check", str(folder / ex["main"])], capture_output=True, text=True)
            if run.returncode != 0:
                failures += 1
                print(f"FAIL {ex['id']}: {(run.stdout + run.stderr).strip().splitlines()[0]}", file=sys.stderr)
            else:
                print(f"ok   {ex['id']}")
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--snapshots", action="store_true", help="redraw proofs/scripts/art/ from the proof themes (runs zig build test-proofs)")
    parser.add_argument("--check", action="store_true", help="compile every example with zig-out/bin/bespoke")
    args = parser.parse_args()
    if args.snapshots:
        for path in snapshot():
            print(f"wrote {path.relative_to(ROOT)} ({path.stat().st_size:,} bytes)")
    if args.check:
        cli = ROOT / "zig-out" / "bin" / "bespoke"
        if not cli.exists():
            raise SystemExit("zig-out/bin/bespoke not found; run `zig build` first")
        return check(cli)
    if not args.snapshots:
        print(f"{len(manifest())} examples, bundle {len(bundle()):,} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
