"""D-175: the browser exports a generated project uses are the supported ones.

The list lives in docs/API.md ("Browser module exports"). This test fails when a listed export
is no longer exported by src/wasm.zig, or when the page or smoke test that `bespoke init`
generates calls an export the list omits, since a generated project then depends on it.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parent.parent
API = ROOT / "docs" / "API.md"
WASM = ROOT / "src" / "wasm.zig"
SCAFFOLD = ROOT / "src" / "scaffold"


def supported_exports() -> set[str]:
    text = API.read_text(encoding="utf-8")
    section = text.split("## Browser module exports", 1)[1].split("\n## ", 1)[0]
    first_paragraph = section.strip().split("\n\n", 1)[0]
    return set(re.findall(r"`(wasm_[a-z0-9_]+)`", first_paragraph))


def module_exports() -> set[str]:
    return set(re.findall(r'\.name = "(wasm_[a-z0-9_]+)"', WASM.read_text(encoding="utf-8")))


def generated_page_calls() -> set[str]:
    calls: set[str] = set()
    for template in ("index.html.tmpl", "smoke.js.tmpl"):
        calls |= set(re.findall(r"\b(wasm_[a-z0-9_]+)\b", (SCAFFOLD / template).read_text(encoding="utf-8")))
    return calls


class BrowserExportTests(unittest.TestCase):
    def test_the_list_is_the_supported_export_names(self):
        self.assertEqual(len(supported_exports()), 21)

    def test_every_supported_export_is_exported(self):
        missing = supported_exports() - module_exports()
        self.assertEqual(missing, set(), f"listed in docs/API.md but not exported: {sorted(missing)}")

    def test_generated_projects_call_only_supported_exports(self):
        unlisted = generated_page_calls() - supported_exports()
        self.assertEqual(unlisted, set(), f"a generated page calls exports docs/API.md does not support: {sorted(unlisted)}")


if __name__ == "__main__":
    unittest.main()
