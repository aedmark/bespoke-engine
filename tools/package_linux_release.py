#!/usr/bin/env python3
"""Archive both Linux x86_64 candidates from `zig build release-linux`."""

import argparse
import os
from pathlib import Path
import re
import subprocess

if __package__:
    from .check_version import check_cli, manifest_version
    from .release_archive import ROOT, validate_version, write_archive
else:
    from check_version import check_cli, manifest_version
    from release_archive import ROOT, validate_version, write_archive


def requirement(elf: str, desktop: bool) -> str:
    if not re.search(r"^\s*Machine:\s+Advanced Micro Devices X86-64\s*$", elf, re.MULTILINE):
        raise ValueError("expected a Linux x86_64 ELF executable")
    libs = re.findall(r"\(NEEDED\)\s+Shared library: \[([^\]]+)\]", elf)
    has_loader = re.search(r"^\s*INTERP\s", elf, re.MULTILINE) is not None
    if desktop:
        versions = re.findall(r"Name: GLIBC_([0-9]+(?:\.[0-9]+)+)\s", elf)
        if not (has_loader and {"libSDL2-2.0.so.0", "libc.so.6"} <= set(libs) and versions):
            raise ValueError("desktop candidate must dynamically link SDL2 and glibc")
        latest = max(versions, key=lambda v: tuple(map(int, v.split("."))))
        return f"Requires a Linux x86_64 desktop, glibc {latest} or newer, and the system SDL2 runtime."
    if libs or has_loader:
        raise ValueError("static candidate must not need a dynamic loader or shared libraries")
    return "Runs headless on Linux x86_64 without Zig, SDL2, or a system libc."


def package_linux(output_dir: Path) -> list[Path]:
    version = manifest_version(ROOT / "build.zig.zon")
    validate_version(version)
    license_bytes = (ROOT / "LICENSE").read_bytes()
    sample = (ROOT / "scenarios" / "night_watch.bespoke").read_bytes()
    candidates = []
    for kind in ("static", "desktop"):
        executable = ROOT / "zig-out" / "release" / f"linux-{kind}" / "bespoke"
        elf = subprocess.check_output(
            ["readelf", "-WhldV", executable], text=True, env={**os.environ, "LC_ALL": "C"}
        )
        desktop = kind == "desktop"
        requirements = requirement(elf, desktop)
        check_cli(executable, "bespoke", version)
        play = "./bespoke run night_watch.bespoke"
        if not desktop:
            play += " --ticks 20"
        readme = f"""# BeSpoke Engine {version}: Linux {kind}

{requirements}

Verify the extracted files with `sha256sum -c SHA256SUMS`, then try the sample:

    {play}

The static CLI runs batch simulations and prints the story; use the SDL2
desktop download for a window and interactive play. The desktop build also
accepts `--headless --ticks 20`. Both downloads run scripts and compiled
`.bspk` packages, and support `check`, `compile`, and `init`.

To scaffold a project, obtain the matching BeSpoke source tree and run:

    ./bespoke init my_game --engine /path/to/bespoke-source

Scaffolding itself needs no Zig. Building the project needs Zig 0.17.1
and the SDL2 development libraries for native builds.
"""
        candidates.append((f"bespoke-linux-x86_64-{kind}-{version}", {
            "README.md": readme.encode(),
            "LICENSE": license_bytes,
            "bespoke": executable.read_bytes(),
            "night_watch.bespoke": sample,
        }))
    return [write_archive(output_dir, name, files, executables=("bespoke",)) for name, files in candidates]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=ROOT / "dist" / "release")
    args = parser.parse_args()
    try:
        for path in package_linux(args.output_dir):
            print(path)
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        parser.exit(1, f"{exc}\n")


if __name__ == "__main__":
    main()
