#!/usr/bin/env python3
"""Require the package manifest and both public CLIs to report one version."""

from __future__ import annotations

import pathlib
import re
import subprocess
import sys


VERSION_RE = re.compile(r'^\s*\.version\s*=\s*"([^"]+)"\s*,\s*$', re.MULTILINE)


def manifest_version(path: pathlib.Path) -> str:
    match = VERSION_RE.search(path.read_text(encoding="utf-8"))
    if match is None:
        raise ValueError(f"{path}: missing .version string")
    return match.group(1)


def check_cli(path: pathlib.Path, name: str, version: str) -> None:
    result = subprocess.run(
        [path, "--version"],
        check=True,
        capture_output=True,
        text=True,
    )
    expected = f"{name} {version}\n"
    if result.stdout != expected or result.stderr:
        raise ValueError(
            f"{path} --version returned stdout={result.stdout!r}, "
            f"stderr={result.stderr!r}; expected stdout={expected!r}"
        )


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print("usage: check_version.py BUILD.ZIG.ZON BESPOKE BESPOKE-PROOFS", file=sys.stderr)
        return 2
    version = manifest_version(pathlib.Path(argv[1]))
    check_cli(pathlib.Path(argv[2]), "bespoke", version)
    check_cli(pathlib.Path(argv[3]), "bespoke-proofs", version)
    print(f"version {version}: manifest and CLIs agree")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
