#!/usr/bin/env python3
"""Check extracted P42-01 Linux downloads; requires bubblewrap, Zig, and SDL2."""

import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile

from check_version import manifest_version
from release_archive import ROOT


def check() -> None:
    version = manifest_version(ROOT / "build.zig.zon")
    with tempfile.TemporaryDirectory(prefix="bespoke-release-") as temp:
        root = Path(temp)
        stage = root / "static"
        stage.mkdir()
        for kind, destination in (("static", stage), ("desktop", root)):
            name = f"bespoke-linux-x86_64-{kind}-{version}"
            with tarfile.open(ROOT / "dist" / "release" / f"{name}.tar.gz") as archive:
                archive.extractall(destination, filter="data")
            subprocess.run(["sha256sum", "-c", "SHA256SUMS"], cwd=destination / name, check=True)

        engine = stage / "engine"
        engine.mkdir()
        for file in ("build.zig", "build.zig.zon"):
            shutil.copyfile(ROOT / file, engine / file)
        shutil.copytree(ROOT / "src", engine / "src")
        static = f"/bespoke-linux-x86_64-static-{version}"
        # The namespace has only the download and the source tree; procfs gives Zig's
        # realPathFile access to /proc/self/fd, without exposing host files or libraries.
        isolation = ["bwrap", "--unshare-pid", "--clearenv", "--bind", stage, "/", "--proc", "/proc"]

        def isolated(*args: str, cwd: str = static, success: bool = True) -> str:
            result = subprocess.run(
                [*isolation, "--chdir", cwd, "--", f"{static}/bespoke", *args],
                stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30,
            )
            if result.returncode != (0 if success else 1):
                raise RuntimeError(f"{args} exited {result.returncode}: {result.stdout}{result.stderr}")
            return result.stdout

        if isolated("--version") != f"bespoke {version}\n":
            raise RuntimeError("static download version mismatch")
        if "Music: Chase" not in isolated("run", "night_watch.bespoke", "--ticks", "20"):
            raise RuntimeError("the static CLI did not play the sample through the alarm")
        isolated("compile", "night_watch.bespoke", "-o", "night_watch.bspk")
        if "Music: Chase" not in isolated("run", "night_watch.bspk", "--ticks", "20"):
            raise RuntimeError("the static CLI did not play the compiled sample")
        if "pass --engine" not in isolated("init", "smoke_game", cwd="/", success=False):
            raise RuntimeError("the portable init did not explain the missing source path")
        isolated("init", "smoke_game", "--engine", "/engine", cwd="/")
        project = stage / "smoke_game"
        if (project / "LICENSE-BeSpoke").read_bytes() != (ROOT / "LICENSE").read_bytes():
            raise RuntimeError("static init changed the BeSpoke license notice")
        if (project / "LICENSE").exists():
            raise RuntimeError("static init assigned a project-wide license")
        print("Static download: source play, package play, and init pass without Zig or SDL2.", flush=True)
        shutil.copyfile(ROOT / "LICENSE", engine / "LICENSE")
        subprocess.run(["zig", "build", "test"], cwd=project, check=True, timeout=180)
        print("Generated project: zig build test passes.", flush=True)

        desktop = root / f"bespoke-linux-x86_64-desktop-{version}"
        env = {**os.environ, "SDL_VIDEODRIVER": "offscreen", "SDL_AUDIODRIVER": "dummy"}
        try:
            result = subprocess.run(
                ["./bespoke", "run", "night_watch.bespoke"], cwd=desktop, env=env,
                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=3,
            )
        except subprocess.TimeoutExpired as exc:
            output = exc.stdout or b""
            if b"OPENED GRAPHICAL DISPLAY WINDOW" in output:
                print("Desktop download: SDL initializes the offscreen window.", flush=True)
                return
        else:
            output = result.stdout
        raise RuntimeError(f"SDL desktop candidate did not keep its window open: {output.decode(errors='replace')}")


if __name__ == "__main__":
    check()
