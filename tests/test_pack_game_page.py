import base64
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

from tools.pack_game_page import pack


TOOL = Path(__file__).resolve().parents[1] / "tools" / "pack_game_page.py"
LOADER = "WebAssembly.instantiateStreaming(fetch('game.wasm'), {})"
WASM = b"\x00asm\x01\x00\x00\x00"


class PackGamePageTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.web = self.root / "web"
        self.web.mkdir()
        self.index = self.web / "index.html"
        self.index.write_text(f"<body><script>{LOADER}.then(start)</script></body>", encoding="utf-8")
        (self.web / "game.wasm").write_bytes(WASM)

    def test_preserves_bootstrap_and_embeds_wasm_and_license(self):
        page = pack(self.web)
        self.assertNotIn("fetch(", page)
        self.assertIn(".then(start)</script>", page)
        self.assertIn('id="bespoke-license"', page)
        self.assertIn("Copyright ©", page)
        self.assertEqual(WASM, base64.b64decode(re.search(r"atob\('([^']+)'\)", page)[1]))

    def test_requires_a_single_generated_loader(self):
        self.index.write_text(f"<body><script>{LOADER};{LOADER}</script></body>", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "exactly one"):
            pack(self.web)

    def test_refuses_a_non_wasm_payload(self):
        (self.web / "game.wasm").write_bytes(b"not wasm")
        with self.assertRaisesRegex(ValueError, "not a WebAssembly module"):
            pack(self.web)

    def test_refuses_to_replace_an_existing_page(self):
        out = self.root / "upload" / "index.html"
        cmd = [sys.executable, str(TOOL), str(self.web), str(out)]
        subprocess.run(cmd, check=True, capture_output=True)
        self.assertEqual([out], list(out.parent.iterdir()))
        old = out.read_bytes()
        result = subprocess.run(cmd, capture_output=True, text=True)
        self.assertEqual(1, result.returncode)
        self.assertIn("refusing to overwrite", result.stderr)
        self.assertEqual(old, out.read_bytes())


class StudioExportShapeTests(unittest.TestCase):
    """The Studio swaps the same loader the packer swaps (P47-07, D-207)."""

    def test_studio_loader_is_the_packer_loader_in_each_init_shell(self):
        from tools.build_studio import SHELL_LOADER, SHELLS
        from tools.pack_game_page import LOADER as PACKER_LOADER

        for kind, path in SHELLS.items():
            with self.subTest(kind=kind):
                shell = path.read_text(encoding="utf-8").replace("{{name}}", "sunken_vault")
                matches = list(PACKER_LOADER.finditer(shell))
                self.assertEqual(len(matches), 1)
                self.assertEqual(matches[0][0], SHELL_LOADER.replace("{{name}}", "sunken_vault"))
                self.assertEqual(shell.count("</body>"), 1)
