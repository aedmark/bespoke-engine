from contextlib import redirect_stderr, redirect_stdout
import io
from pathlib import Path
import tempfile
import unittest

from tools.check_web_budgets import check_sizes


class WebBudgetTests(unittest.TestCase):
    def test_exact_limit_is_allowed_but_growth_fails(self):
        with tempfile.TemporaryDirectory() as tmp, redirect_stdout(io.StringIO()) as log:
            page = Path(tmp) / "index.html"
            page.write_bytes(b"abcd")
            self.assertTrue(check_sizes([(page, 4)]))
            self.assertFalse(check_sizes([(page, 3)]))
            self.assertIn("4 / 3 bytes", log.getvalue())

    def test_missing_artifact_is_a_failure(self):
        with tempfile.TemporaryDirectory() as tmp, redirect_stderr(io.StringIO()) as log:
            wasm = Path(tmp) / "missing.wasm"
            self.assertFalse(check_sizes([(wasm, 4)]))
            self.assertIn("missing.wasm", log.getvalue())
