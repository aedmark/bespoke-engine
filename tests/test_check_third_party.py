import hashlib
import importlib.util
import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout, redirect_stderr
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("check_third_party", ROOT / "tools" / "check_third_party.py")
tp = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(tp)

# Invented stand-ins: the lint must work without the real third-party text in the tests.
LINE = "The kettle sings at midnight."


def digest(text):
    return hashlib.sha256(" ".join(text.lower().split()).encode()).hexdigest()


TERMS = {"sources": {"Example Saga": {"names": ["Zorbin", "Quill Harbour", "zorb"], "lines_sha256": [digest(LINE)]}}}


class ThirdPartyLintTests(unittest.TestCase):
    def make_repo(self, files):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        (root / "tools").mkdir()
        (root / "tools" / "third_party_terms.json").write_text(json.dumps(TERMS), encoding="utf-8")
        for rel, text in files.items():
            path = root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
        return root

    def counts(self, root):
        return tp.scan(root)[0]

    def test_names_match_whole_words_camel_case_and_identifiers(self):
        root = self.make_repo({"src/a.zig": "Zorbin ZorbinHat zorb_puzzle --zorb\nZorbins Zorbinx zorbing Quill Harbour\n"})
        # Zorbin, ZorbinHat, zorb_puzzle, --zorb, Quill Harbour; not Zorbins, Zorbinx, zorbing.
        self.assertEqual({"src/a.zig": {"Example Saga": 5}}, self.counts(root))

    def test_quoted_lines_match_by_digest_even_inside_highlighted_html_json(self):
        page = (
            '<script type="application/json">{"html": "<span class=\\"code-str\\">\\"The kettle '
            '<b>sings</b> at midnight.\\"<\\/span>"}</script>\n'
        )
        root = self.make_repo({"site/index.html": page, "proofs/p.zig": '    \\\\  say A: "the  KETTLE sings at midnight."\n'})
        self.assertEqual({"site/index.html": {"Example Saga": 1}, "proofs/p.zig": {"Example Saga": 1}}, self.counts(root))

    def test_the_embedded_wasm_region_and_history_are_not_scanned(self):
        page = "<!-- SITE_SIMULATOR_START -->\nZorbin Zorbin\n<!-- SITE_SIMULATOR_END -->\nZorbin\n"
        root = self.make_repo({"site/index.html": page, "docs/DECISIONS.md": "Zorbin\n", "docs/archive/x.md": "Zorbin\n"})
        self.assertEqual({"site/index.html": {"Example Saga": 1}}, self.counts(root))

    def test_a_rise_above_baseline_fails_and_the_baseline_only_shrinks(self):
        root = self.make_repo({"src/a.zig": "Zorbin\n"})
        with redirect_stdout(io.StringIO()):
            self.assertEqual(0, tp.main(["--root", str(root), "--update-baseline"]))
            self.assertEqual(0, tp.main(["--root", str(root)]))
        (root / "src" / "a.zig").write_text("Zorbin Zorbin\n", encoding="utf-8")
        errors, _ = tp.check(root)
        self.assertEqual(1, len(errors))
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            self.assertEqual(1, tp.main(["--root", str(root), "--update-baseline"]))
        self.assertEqual(1, tp.load_baseline(root)["src/a.zig"]["Example Saga"])
        (root / "src" / "a.zig").write_text("nothing borrowed\n", encoding="utf-8")
        errors, notes = tp.check(root)
        self.assertEqual([], errors)
        self.assertEqual(1, len(notes))

    def test_the_repository_is_at_or_under_its_baseline(self):
        errors, _ = tp.check(ROOT)
        self.assertEqual([], errors)


if __name__ == "__main__":
    unittest.main()
