#!/usr/bin/env python3
"""Run the marked shell blocks in the first-game tutorial in order."""

import os
from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent
TUTORIAL = ROOT / "docs" / "FIRST_GAME.md"
STEP = re.compile(r"^<!-- tutorial:run -->\n\n`{3}bash\n(.*?)^`{3}$", re.MULTILINE | re.DOTALL)


def main() -> None:
    text = TUTORIAL.read_text(encoding="utf-8")
    blocks = STEP.findall(text)
    if not blocks or len(blocks) != text.count("<!-- tutorial:run -->"):
        raise SystemExit("missing or malformed tutorial:run block")
    with tempfile.TemporaryDirectory(prefix="bespoke-tutorial-") as work:
        subprocess.run(
            ["bash", "-euo", "pipefail", "-c", "\n\n".join(blocks)],
            cwd=ROOT,
            env={**os.environ, "BESPOKE_TUTORIAL_DIR": work},
            check=True,
        )


if __name__ == "__main__":
    main()
