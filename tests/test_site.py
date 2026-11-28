import base64
import importlib.util
import json
import re
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
# D-086, D-094, D-122: each standalone page's data-deck names its proof in the deck table.
DECK_BY_PAGE = {
    "tavern.html": 0,
    "pips.html": 1,
    "beard.html": 2,
    "village.html": 3,
    "donkey.html": 4,
    "tides.html": 5,
    "grog.html": 6,
    "barbs.html": 7,
    "saltmarket.html": 8,
    "weathercock.html": 9,
    "bell-tower.html": 10,
    "fire-escape.html": 11,
    "observatory.html": 12,
    "valerius.html": 13,
    "lamplighter.html": 14,
    "long-gallery.html": 15,
    "word-foundry.html": 16,
    "cinder-table.html": 17,
    "tide-beacon.html": 18,
}


class SiteBuildTests(unittest.TestCase):
    def test_each_proof_page_plays_its_own_deck_and_is_current(self):
        wrapper = (ROOT / "tools" / "proof_page.js").read_text(encoding="utf-8")
        self.assertIn(build_site.PLACEHOLDER, wrapper)
        self.assertIn("window.bespokePageState", wrapper)
        self.assertIn("audioPlaying", wrapper)
        self.assertEqual(sorted(DECK_BY_PAGE), sorted(p.name for p in build_site.PROOF_PAGE_PATHS))
        for path in build_site.PROOF_PAGE_PATHS:
            page = path.read_text(encoding="utf-8")
            index = int(re.search(r'id="game-canvas"[^>]*data-deck="(\d+)"', page).group(1))
            self.assertEqual(DECK_BY_PAGE[path.name], index, path.name)
            for element in ("game-status", "btn-next", "btn-sound", "btn-restart"):
                self.assertIn(f'id="{element}"', page, path.name)
            if build_site.WASM_ARTIFACT.exists():
                self.assertEqual(page, build_site.render_proof_page(page), path.name)

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


class GalleryTests(unittest.TestCase):
    """P30-03 (D-068), D-122: the gallery links one standalone page per proof."""

    def test_gallery_cards_open_each_proofs_own_page(self):
        entries = [
            {"id": "a", "title": "A & B", "tag": "t", "blurb": "b", "deck": 4, "page": "donkey.html", "flag": "lamp-point"},
            {"id": "c", "title": "C", "tag": "t", "blurb": "b", "deck": 0, "page": "tavern.html", "flag": "tavern"},
        ]
        block = build_site.render_gallery_block(entries)
        self.assertIn('href="donkey.html"', block)
        self.assertIn('href="tavern.html"', block)
        self.assertIn("A &amp; B", block)
        self.assertIn("Proof 01", block)
        self.assertIn("Proof 02", block)
        self.assertNotIn("proof-lab", block)
        with self.assertRaises(SystemExit):
            build_site.render_gallery_block([{**entries[0], "page": "missing.html"}])
        self.assertTrue(block.startswith("      " + build_site.GALLERY_START))

    def test_homepage_mounts_only_harbour_and_links_every_proof_page(self):
        homepage = build_site.HTML_PATH.read_text(encoding="utf-8")
        self.assertEqual(['harbour.html'], re.findall(r'<iframe[^>]+src="([^"]+)"', homepage))
        self.assertIn('href="sunken-vault.html"', homepage)
        self.assertTrue(build_site.SUNKEN_VAULT_PATH.is_file())
        self.assertLess(homepage.index('id="harbour-demo"'), homepage.index('id="scenarios"'))
        self.assertNotIn(build_site.START_MARKER, homepage)
        self.assertNotIn("proof-lab", homepage)
        self.assertEqual(homepage, build_site.render_site(homepage))
        entries = build_site.gallery_entries()
        self.assertCountEqual([e["page"] for e in entries], list(build_site.PROOF_PAGE_NAMES))
        for entry in entries:
            page = (build_site.HTML_PATH.parent / entry["page"]).read_text(encoding="utf-8")
            self.assertIn(f'data-deck="{entry["deck"]}"', page, entry["page"])

    def test_the_real_gallery_covers_every_proof_once_with_valid_decks_and_flags(self):
        gallery = json.loads(build_site.GALLERY_PATH.read_text(encoding="utf-8"))["proofs"]
        self.assertEqual(len(gallery), 19)
        self.assertEqual(len(gallery), len({e["id"] for e in gallery}))
        decks = sorted(e["deck"] for e in gallery)
        self.assertEqual(list(range(len(decks))), decks)
        proofs_main = (ROOT / "proofs" / "main.zig").read_text(encoding="utf-8")
        for entry in gallery:
            self.assertIn(f'.name = "{entry["flag"]}"', proofs_main, entry["id"])
            self.assertTrue((build_site.HTML_PATH.parent / entry["page"]).is_file(), entry["id"])
            for key in ("id", "title", "tag", "blurb", "page", "deck", "flag"):
                self.assertIn(key, entry, entry["id"])


if __name__ == "__main__":
    unittest.main()


class FreshBuildTests(unittest.TestCase):
    """A built game page older than what it is made from is refused, not compared."""

    def test_a_build_older_than_an_input_is_refused(self):
        import os
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            built = root / "index.html"
            built.write_text("page", encoding="utf-8")
            source = root / "game" / "main.bespoke"
            source.parent.mkdir()
            source.write_text("scene Yard:", encoding="utf-8")
            os.utime(built, (1000, 1000))
            os.utime(source, (2000, 2000))
            with self.assertRaises(SystemExit) as caught:
                build_site.require_fresh(built, (source.parent,), "rebuild it")
            self.assertIn("main.bespoke", str(caught.exception))
            # Rebuilt after the change, it passes.
            os.utime(built, (3000, 3000))
            build_site.require_fresh(built, (source.parent,), "rebuild it")

    def test_both_game_pages_are_guarded(self):
        self.assertIn(ROOT / "scenarios" / "sunken_vault", build_site.SUNKEN_VAULT_INPUTS)
        self.assertIn(ROOT / "scenarios" / "harbour", build_site.HARBOUR_INPUTS)
        self.assertIn(ROOT / "src", build_site.ENGINE_INPUTS)
