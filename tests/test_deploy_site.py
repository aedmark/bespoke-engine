import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("deploy_site", ROOT / "tools" / "deploy_site.py")
deploy = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(deploy)

PAGE = """<!DOCTYPE html>
<html><head>
  <title>Stage &amp; Spine</title>
  <meta name="description" content="A test page with &quot;quotes&quot;.">
</head>
<body><p>hi</p>
</body></html>
"""


class ExportTests(unittest.TestCase):
    def export(self, site_url=None):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        page = Path(tmp.name) / "index.html"
        page.write_text(PAGE, encoding="utf-8")
        out = Path(tmp.name) / "out"
        deploy.export(out, site_url, page_path=page, check_current=False)
        return (out / "index.html").read_text(encoding="utf-8"), (out / "sw.js").read_text(encoding="utf-8")

    def test_metadata_comes_from_the_page_and_is_escaped(self):
        index, _ = self.export()
        self.assertIn('<meta property="og:title" content="Stage &amp; Spine">', index)
        self.assertIn('content="A test page with &quot;quotes&quot;."', index)
        self.assertNotIn("og:url", index)
        self.assertNotIn("canonical", index)

    def test_site_url_adds_canonical_and_og_url_with_a_trailing_slash(self):
        index, _ = self.export("https://example.neocities.org")
        self.assertIn('<link rel="canonical" href="https://example.neocities.org/">', index)
        self.assertIn('<meta property="og:url" content="https://example.neocities.org/">', index)
        with self.assertRaises(deploy.DeployError):
            self.export("http://example.neocities.org/")

    def test_service_worker_is_registered_only_over_http_and_named_by_content(self):
        index, worker = self.export()
        self.assertIn("location.protocol.startsWith('http')", index)
        self.assertLess(index.index(deploy.BODY_MARKER), index.index("</body>"))
        digest = __import__("hashlib").sha256(index.encode()).hexdigest()[:16]
        self.assertIn(f"const CACHE = 'bespoke-site-{digest}';", worker)
        # A different page gets a different cache, so a deploy replaces the old one.
        _, other = self.export("https://example.neocities.org/")
        self.assertNotEqual(worker, other)

    def test_a_page_already_exported_is_refused(self):
        with self.assertRaises(deploy.DeployError):
            deploy.render_export(PAGE.replace("</head>", deploy.HEAD_MARKER + "</head>"), None)

    def test_the_repository_page_is_current_and_exports(self):
        # Guards the real page: export refuses a stale one, as build_site.py --check does.
        if not (ROOT / "zig-out" / "bin" / "bespoke-proofs.wasm").exists():
            self.skipTest("run `zig build wasm-proofs` first")
        with tempfile.TemporaryDirectory() as tmp:
            written = deploy.export(Path(tmp), None)
        self.assertEqual(["index.html", "sw.js", "barbs.html"], [p.name for p in written])


class ExportOnlyTests(unittest.TestCase):
    def test_the_tool_has_no_upload_command(self):
        # Uploading is done by hand (D-074); the tool must not grow a network path back.
        with self.assertRaises(SystemExit):
            deploy.main(["upload"])
        self.assertFalse(hasattr(deploy, "upload"))


if __name__ == "__main__":
    unittest.main()
