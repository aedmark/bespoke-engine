#!/usr/bin/env python3
"""Build and test The Sunken Vault (P49-03) using `bespoke init --template text`."""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "scenarios" / "sunken_vault"


def run(*command: str | Path, cwd: Path) -> None:
    subprocess.run(command, cwd=cwd, check=True)


def replace_once(text: str, old: str, new: str) -> str:
    if text.count(old) != 1:
        raise ValueError(f"generated file must contain {old!r} exactly once")
    return text.replace(old, new, 1)


def build(output: Path, browser_check: bool) -> None:
    if output.suffix != ".html" or output.exists():
        raise ValueError("choose a new .html output path")
    run("zig", "build", "-j2", cwd=ROOT)
    cli = ROOT / "zig-out" / "bin" / "bespoke"
    with tempfile.TemporaryDirectory(prefix="bespoke-sunken-vault-") as tmp:
        work = Path(tmp)
        run(cli, "init", "sunken_vault", "--template", "text", "--engine", ROOT, cwd=work)
        project = work / "sunken_vault"
        shutil.copyfile(GAME / "main.bespoke", project / "scripts" / "main.bespoke")
        for png in sorted((GAME / "art").glob("*.png")):
            shutil.copyfile(png, project / "scripts" / png.name)
        shutil.copyfile(GAME / "game_test.zig", project / "src" / "game_test.zig")
        shutil.copyfile(GAME / "web.zig", project / "src" / "web.zig")

        web = project / "web" / "index.html"
        page = web.read_text(encoding="utf-8")
        page = replace_once(page, "<title>sunken_vault</title>", "<title>The Sunken Vault</title>")
        page = replace_once(page, "<h1>sunken_vault</h1>", "<h1>The Sunken Vault</h1>")
        page = replace_once(
            page,
            '<p class="help">Commands: look, north, south, take lantern, light lantern.</p>',
            '<p class="help">Commands: look, inventory, wait, north/south/east/west/up/down, take, read, light, turn, unlock.</p>',
        )
        web.write_text(page, encoding="utf-8")

        run(cli, "check", "scripts/main.bespoke", cwd=project)
        run("zig", "build", "test", "web", "-j2", "--summary", "all", cwd=project)
        run("node", GAME / "check_wasm.js", project / "zig-out" / "web" / "sunken_vault.wasm", cwd=project)
        output.parent.mkdir(parents=True, exist_ok=True)
        run(sys.executable, ROOT / "tools" / "pack_game_page.py", "zig-out/web", output, cwd=project)
        if browser_check:
            run("node", GAME / "check_chrome.js", output, cwd=project)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="new HTML file for the packed standalone build")
    parser.add_argument("--chrome", action="store_true", help="also verify the packed HTML in Chrome")
    args = parser.parse_args()
    try:
        build(args.output.resolve(), args.chrome)
    except (OSError, ValueError, subprocess.CalledProcessError) as err:
        parser.exit(1, f"Sunken Vault build failed: {err}\n")


if __name__ == "__main__":
    main()
