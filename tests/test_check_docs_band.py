"""The band rows quoted in prose against the rows src/display/band.zig computes (P43-07)."""
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load():
    spec = importlib.util.spec_from_file_location("check_docs", ROOT / "tools" / "check_docs.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class BandRowsTest(unittest.TestCase):
    def test_derives_the_rows_the_band_module_asserts(self):
        top, bottom = load().band_rows(ROOT)
        self.assertEqual((504, 582), (top, bottom))

    def test_current_phrasings_pass(self):
        docs = load()
        text = (
            "the band's tallest top of 504, and it grows upward from y 582 at 1280x720\n"
            "four rows plus the command bar (504 pixels at 1280x720)\n"
            "a prop's whole marker clears 504 only from world y 9 down\n"
            "a drawn string in rows 504 to 582\n"
        )
        self.assertEqual([], docs.check_band_numbers({ROOT / "docs" / "TESTING.md": text}))

    def test_a_quoted_top_that_differs_fails(self):
        docs = load()
        errors = docs.check_band_numbers({ROOT / "docs" / "TESTING.md": "the band's tallest top of 500"})
        self.assertEqual(1, len(errors))
        self.assertIn("not 500", errors[0])

    def test_a_quoted_bottom_that_differs_fails(self):
        docs = load()
        errors = docs.check_band_numbers({ROOT / "docs" / "TESTING.md": "the band grows upward from 578"})
        self.assertEqual(1, len(errors))
        self.assertIn("not 578", errors[0])

    def test_a_stale_row_pair_fails(self):
        docs = load()
        errors = docs.check_band_numbers({ROOT / "docs" / "TESTING.md": "a drawn string in rows 504 to 578 under the band"})
        self.assertEqual(1, len(errors))
        self.assertIn("not 504 to 578", errors[0])

    def test_a_number_outside_a_band_sentence_is_ignored(self):
        docs = load()
        self.assertEqual([], docs.check_band_numbers({ROOT / "docs" / "TESTING.md": "The run took 504 ms."}))

    def test_archived_numbers_are_history(self):
        docs = load()
        path = ROOT / "docs" / "archive" / "ROADMAP_2026_11.md"
        self.assertEqual([], docs.check_band_numbers({path: "the band's tallest top of 500"}))


if __name__ == "__main__":
    unittest.main()
