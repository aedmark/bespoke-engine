import base64
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
