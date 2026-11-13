import hashlib
import importlib.util
import io
import json
import os
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from unittest import mock

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
KEY = "test-key-not-real"


class FakeNeocities(BaseHTTPRequestHandler):
    """Answers /api/list from `remote` and records /api/upload bodies."""

    remote: dict = {}
    uploads: list = []
    auth: list = []

    def log_message(self, *args):
        pass

    def _reply(self, payload):
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        FakeNeocities.auth.append(self.headers.get("Authorization"))
        files = [{"path": p, "is_directory": False, "sha1_hash": h} for p, h in FakeNeocities.remote.items()]
        self._reply({"result": "success", "files": files})

    def do_POST(self):
        FakeNeocities.auth.append(self.headers.get("Authorization"))
        length = int(self.headers["Content-Length"])
        FakeNeocities.uploads.append(self.rfile.read(length))
        self._reply({"result": "success", "message": "your file(s) have been successfully uploaded"})


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
            self.assertEqual(["index.html", "sw.js"], [p.name for p in written])


class UploadTests(unittest.TestCase):
    def setUp(self):
        self.server = HTTPServer(("127.0.0.1", 0), FakeNeocities)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.shutdown)
        FakeNeocities.remote = {}
        FakeNeocities.uploads = []
        FakeNeocities.auth = []
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = Path(tmp.name)
        (self.dir / "index.html").write_text("page", encoding="utf-8")
        (self.dir / "sw.js").write_text("worker", encoding="utf-8")
        env = {deploy.KEY_ENV: KEY, deploy.API_ENV: f"http://127.0.0.1:{self.server.server_port}/api"}
        patcher = mock.patch.dict(os.environ, env)
        patcher.start()
        self.addCleanup(patcher.stop)

    def run_upload(self, confirm):
        out = io.StringIO()
        self.assertEqual(0, deploy.upload(self.dir, confirm, out))
        return out.getvalue()

    def test_dry_run_lists_only_changed_files_and_uploads_nothing(self):
        FakeNeocities.remote = {"index.html": hashlib.sha1(b"page").hexdigest(), "old.html": "x"}
        text = self.run_upload(False)
        self.assertIn("would upload sw.js", text)
        self.assertNotIn("index.html", text)
        self.assertEqual([], FakeNeocities.uploads)
        self.assertNotIn(KEY, text)

    def test_yes_uploads_changed_files_with_the_key_in_the_header_only(self):
        text = self.run_upload(True)
        self.assertIn("Uploaded 2 file(s).", text)
        self.assertNotIn(KEY, text)
        self.assertEqual(1, len(FakeNeocities.uploads))
        body = FakeNeocities.uploads[0]
        self.assertIn(b'name="index.html"', body)
        self.assertIn(b'name="sw.js"', body)
        self.assertNotIn(KEY.encode(), body)
        self.assertTrue(all(a == f"Bearer {KEY}" for a in FakeNeocities.auth))

    def test_nothing_changed_uploads_nothing(self):
        FakeNeocities.remote = {n: hashlib.sha1(c).hexdigest() for n, c in (("index.html", b"page"), ("sw.js", b"worker"))}
        self.assertIn("nothing to upload", self.run_upload(True))
        self.assertEqual([], FakeNeocities.uploads)

    def test_missing_key_or_export_is_refused_before_any_request(self):
        with mock.patch.dict(os.environ, {deploy.KEY_ENV: ""}):
            with self.assertRaises(deploy.DeployError):
                deploy.upload(self.dir, True)
        with self.assertRaises(deploy.DeployError):
            deploy.upload(self.dir / "missing", True)
        self.assertEqual([], FakeNeocities.auth)


if __name__ == "__main__":
    unittest.main()
