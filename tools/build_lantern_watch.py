#!/usr/bin/env python3
"""Build and test Lantern Watch on the BeSpoke host API."""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "scenarios" / "lantern_watch"


def run(*command: str | Path, cwd: Path) -> None:
    subprocess.run(command, cwd=cwd, check=True)


def replace_once(page: str, old: str, new: str) -> str:
    if page.count(old) != 1:
        raise ValueError(f"generated game page must contain {old!r} exactly once")
    return page.replace(old, new, 1)


def build(output: Path, browser_check: bool) -> None:
    if output.suffix != ".html" or output.exists():
        raise ValueError("choose a new .html output path")
    run("zig", "build", "-j2", cwd=ROOT)
    cli = ROOT / "zig-out" / "bin" / "bespoke"
    with tempfile.TemporaryDirectory(prefix="bespoke-lantern-") as tmp:
        work = Path(tmp)
        run(cli, "init", "lantern_watch", "--engine", ROOT, cwd=work)
        project = work / "lantern_watch"
        shutil.copyfile(GAME / "main.bespoke", project / "scripts" / "main.bespoke")
        shutil.copyfile(GAME / "game_test.zig", project / "src" / "game_test.zig")
        shutil.copyfile(GAME / "web.zig", project / "src" / "web.zig")

        web = project / "web" / "index.html"
        page = web.read_text(encoding="utf-8")
        page = replace_once(page, "<title>lantern_watch</title>", "<title>Lantern Watch</title>")
        page = replace_once(page, "const TICK_MS = 50;", "const TICK_MS = 1000;")
        page = replace_once(page, "// 20 ticks a second,", "// One tick a second,")
        text_ui = replace_once(
            (GAME / "text_ui.html").read_text(encoding="utf-8"),
            "<!-- opening prose -->",
            (GAME / "intro.html").read_text(encoding="utf-8").strip(),
        )
        page = replace_once(
            page, '<canvas id="stage" width="1280" height="720"></canvas>',
            '<main id="watch-stage">\n'
            + text_ui
            + '<div id="watch-map" hidden><canvas id="stage" width="1280" height="720" tabindex="0"></canvas></div>',
        )
        page = replace_once(page, "</style>", (
            "  #watch-controls { border: 0; padding: 0; margin: 0; min-inline-size: 0; }\n"
            "  #watch-intro { margin-bottom: 1em; }\n"
            "  #watch-stage { width: min(92vw, 760px); margin: 24px 0; }\n"
            "  #watch-stage canvas { max-width: 100%; }\n"
            "  #transcript { height: clamp(14rem, 48vh, 32rem); overflow-y: auto; padding: 12px 16px; border: 1px solid #3a4555; background: #0c1016; }\n"
            "  #transcript p, #command-help { text-align: left; margin: 0 0 .7em; line-height: 1.55; }\n"
            "  #transcript .command { color: #a8cce3; font-family: monospace; }\n"
            "  #command-form { display: flex; align-items: center; gap: 8px; margin: 12px 0; }\n"
            "  #command { flex: 1; min-width: 0; background: #17202a; color: inherit; border: 1px solid #58697e; padding: 6px 8px; }\n"
            "</style>"
        ))
        page = replace_once(
            page,
            "  // A new game rolls from the clock; the seed stays with the run through rewinds (D-184).\n"
            "  w.wasm_init(0, Date.now() >>> 0, (Math.random() * 0x100000000) >>> 0);",
            "  let started = false;",
        )
        page = replace_once(
            page, "    w.wasm_render_frame();",
            "    drainText();\n"
            "    canvas.dataset.tick = w.wasm_get_tick();\n"
            "    if (map.hidden) return;\n"
            "    w.wasm_render_frame();",
        )
        page = replace_once(
            page, "  window.addEventListener('keydown', (e) => {",
            "  window.addEventListener('keydown', (e) => {\n"
            "    if (!started || map.hidden || e.target !== canvas || e.key === 'Tab') return;",
        )
        page = replace_once(
            page, "  setInterval(() => { w.wasm_step_tick(); draw(); }, TICK_MS);\n  draw();",
            (GAME / "text_ui.js").read_text(encoding="utf-8")
            + "  const start = document.getElementById('start-watch');\n"
            "  start.addEventListener('click', () => {\n"
            "    w.wasm_init(0, Date.now() >>> 0, (Math.random() * 0x100000000) >>> 0);\n"
            "    started = true;\n"
            "    document.getElementById('watch-controls').disabled = false;\n"
            "    document.getElementById('start-prompt').hidden = true;\n"
            "    command.focus();\n"
            "    draw();\n"
            "    setInterval(() => { w.wasm_step_tick(); draw(); }, TICK_MS);\n"
            "  }, { once: true });\n"
            "  start.disabled = false;\n"
            "  start.focus();",
        )
        page = replace_once(
            page, ">Sound: off</button></p>",
            '>Sound: off</button> <label>Volume <input id="volume" type="range" '
            'min="0" max="100" value="30"></label></p>',
        )
        page = replace_once(
            page, "  let pump = null;\n",
            "  let pump = null;\n"
            "  let master = null;\n"
            "  const volume = document.getElementById('volume');\n"
            "  volume.addEventListener('keydown', e => e.stopPropagation());\n"
            "  volume.addEventListener('input', () => {\n"
            "    if (audio && master) master.gain.setTargetAtTime(Number(volume.value) / 100, audio.currentTime, 0.025);\n"
            "  });\n",
        )
        page = replace_once(
            page, "    node.connect(audio.destination);",
            "    const warmth = audio.createBiquadFilter();\n"
            "    warmth.type = 'lowpass';\n"
            "    warmth.frequency.value = 1100;\n"
            "    warmth.Q.value = 0.707;\n"
            "    master = audio.createGain();\n"
            "    master.gain.value = Number(volume.value) / 100;\n"
            "    node.connect(warmth).connect(master).connect(audio.destination);",
        )
        help_start = page.index("<p>Click a mark to walk.")
        help_end = page.index("</p>", help_start) + len("</p>")
        page = page[:help_start] + "</fieldset>\n</main>" + page[help_end:]
        web.write_text(page, encoding="utf-8")

        run(cli, "check", "scripts/main.bespoke", cwd=project)
        run("zig", "build", "test", "web", "-j2", "--summary", "all", cwd=project)
        run("node", GAME / "check_keyboard.js", project / "zig-out" / "web" / "lantern_watch.wasm", cwd=project)
        run(sys.executable, ROOT / "tools" / "pack_game_page.py", "zig-out/web", output, cwd=project)
        if browser_check:
            run("node", ROOT / "tools" / "browser_smoke.js", "--starter", output, cwd=project)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="new HTML file for manual upload")
    parser.add_argument("--chrome", action="store_true", help="also render the exact upload file in Chrome")
    args = parser.parse_args()
    try:
        build(args.output.resolve(), args.chrome)
    except (OSError, ValueError, subprocess.CalledProcessError) as err:
        parser.exit(1, f"Lantern Watch build failed: {err}\n")


if __name__ == "__main__":
    main()
