import base64
import json
import re
import tempfile
import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("build_site", ROOT / "tools" / "build_site.py")
build_site = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(build_site)

WRAPPER = """const WASM_BASE64 = '__BESPOKE_PROOFS_WASM_BASE64__';
WebAssembly.instantiate(decodeBase64(WASM_BASE64), {});
wasm_init(0);
"""
PAYLOAD = b"\0asm\x01\0\0\0"


class SiteBuildTests(unittest.TestCase):
    def test_the_barbs_page_plays_the_duel_deck_and_is_current(self):
        # D-086: the standalone page's deck index names the duel proof in the deck table.
        wrapper = (ROOT / "tools" / "barbs_page.js").read_text(encoding="utf-8")
        index = int(re.search(r"const BARBS_DECK = (\d+);", wrapper).group(1))
        names = re.search(r"const DECK_NAMES = \[(.*?)\];", (ROOT / "tools" / "site_simulator.js").read_text(encoding="utf-8"), re.S).group(1)
        self.assertEqual("Brackwater Barbs", re.findall(r"'([^']*)'", names)[index])
        self.assertIn(build_site.PLACEHOLDER, wrapper)
        page = (ROOT / "site" / "barbs.html").read_text(encoding="utf-8")
        if build_site.WASM_ARTIFACT.exists():
            self.assertEqual(page, build_site.render_barbs(page))

    def test_render_embeds_payload_and_wrapper(self):
        html = "before\n<!-- SITE_SIMULATOR_START -->\n<!-- SITE_SIMULATOR_END -->\nafter\n"
        rendered = build_site.render_page(html, WRAPPER, PAYLOAD)
        self.assertTrue(rendered.startswith("before\n"))
        self.assertTrue(rendered.endswith("\nafter\n"))
        self.assertIn(base64.b64encode(PAYLOAD).decode("ascii"), rendered)
        self.assertIn("WebAssembly.instantiate", rendered)
        self.assertIn("wasm_init(0)", rendered)
        self.assertNotIn(build_site.PLACEHOLDER, rendered)

    def test_render_is_idempotent(self):
        html = "before\n<!-- SITE_SIMULATOR_START -->\n<!-- SITE_SIMULATOR_END -->\nafter\n"
        once = build_site.render_page(html, WRAPPER, PAYLOAD)
        twice = build_site.render_page(once, WRAPPER, PAYLOAD)
        self.assertEqual(once, twice)

    def test_render_requires_both_markers(self):
        with self.assertRaises(SystemExit):
            build_site.render_page("before\nafter\n", WRAPPER, PAYLOAD)
        with self.assertRaises(SystemExit):
            build_site.render_page("<!-- SITE_SIMULATOR_START -->\nafter\n", WRAPPER, PAYLOAD)


if __name__ == "__main__":
    unittest.main()


ZIG_PROOF = r'''const std = @import("std");
pub const DEMO_SCRIPT =
    \\scene: Quay
    \\  say Pilot: "a </script> b"
;
const OTHER = 1;
'''


class GalleryTests(unittest.TestCase):
    """P30-03 (D-068): the gallery and script viewer come from the proofs' real scripts."""

    WORDS = {"scene", "say", "when"}

    def test_extracts_a_zig_multiline_constant_and_a_bespoke_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "demo.zig").write_text(ZIG_PROOF, encoding="utf-8")
            (root / "demo.bespoke").write_text("scene Quay:\n\n", encoding="utf-8")
            self.assertEqual('scene: Quay\n  say Pilot: "a </script> b"\n', build_site.extract_script("demo.zig#DEMO_SCRIPT", root))
            self.assertEqual("scene Quay:\n", build_site.extract_script("demo.bespoke", root))
            with self.assertRaises(SystemExit):
                build_site.extract_script("demo.zig#MISSING", root)

    def test_highlight_escapes_and_marks_keywords_strings_numbers_and_comments(self):
        out = build_site.highlight('# when <x>\nscene Quay: "a <b>" 3 when\n', self.WORDS)
        self.assertEqual(
            '<span class="line"><span class="code-comment"># when &lt;x&gt;</span></span>'
            '<span class="line"><span class="code-kw">scene</span> Quay: <span class="code-str">"a &lt;b&gt;"</span> '
            '<span class="code-num">3</span> <span class="code-kw">when</span></span>',
            out,
        )

    def test_gallery_cards_play_or_point_to_the_desktop_and_embed_scripts_safely(self):
        entries = [
            {"id": "a", "title": "A & B", "tag": "t", "blurb": "b", "source": "demo.zig#DEMO_SCRIPT", "deck": 0, "flag": "a"},
            {"id": "c", "title": "C </script> D", "tag": "t", "blurb": "b", "source": "demo.zig#DEMO_SCRIPT", "deck": None, "flag": "c-proof"},
        ]
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "demo.zig").write_text(ZIG_PROOF, encoding="utf-8")
            block = build_site.render_gallery_block(entries, self.WORDS, root)
        self.assertIn('data-play-deck="0"', block)
        self.assertIn("zig build run-proof -- --c-proof", block)
        self.assertIn("A &amp; B", block)
        self.assertIn('data-view-script="c"', block)
        # The embedded JSON cannot close its own <script> element early, even from a raw title.
        data = block[block.index('id="proof-scripts">') :]
        self.assertEqual(1, data.count("</script>"))
        self.assertTrue(block.startswith("      " + build_site.GALLERY_START))

    def test_the_real_gallery_covers_every_proof_once_with_valid_decks_and_flags(self):
        gallery = json.loads(build_site.GALLERY_PATH.read_text(encoding="utf-8"))["proofs"]
        words = build_site.keywords(build_site.LEXER_PATH.read_text(encoding="utf-8"))
        self.assertIn("remember", words)
        self.assertEqual(len(gallery), len({e["id"] for e in gallery}))
        decks = sorted(e["deck"] for e in gallery if e["deck"] is not None)
        simulator = build_site.SIMULATOR_JS_PATH.read_text(encoding="utf-8")
        names = simulator[simulator.index("const DECK_NAMES = [") : simulator.index("];", simulator.index("const DECK_NAMES = ["))]
        self.assertEqual(list(range(names.count("'") // 2)), decks)
        proofs_main = (ROOT / "proofs" / "main.zig").read_text(encoding="utf-8")
        for entry in gallery:
            self.assertIn(f'.name = "{entry["flag"]}"', proofs_main, entry["id"])
            self.assertGreater(len(build_site.extract_script(entry["source"]).splitlines()), 10, entry["id"])
