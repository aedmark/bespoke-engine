import importlib.util
import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("check_separation", ROOT / "tools" / "check_separation.py")
sep = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(sep)

PROOF = r'''const std = @import("std");
pub const SCRIPT =
    \\scene: Moon Base
    \\cast: Astra, Rover
    \\props: Airlock, Cat
    \\marks: Hangar, DockMark
    \\draft Lift(C, D, E, F) reverse Drop
    \\entity Player
;
fn f(world: anytype) void {
    _ = world.lookup_entity("Beacon");
}
'''


class SeparationLintTests(unittest.TestCase):
    def make_repo(self, engine_source, baseline=None):
        tmp = tempfile.TemporaryDirectory()
        root = Path(tmp.name)
        (root / "proofs").mkdir()
        (root / "src").mkdir()
        (root / "tools").mkdir()
        (root / "proofs" / "moon.zig").write_text(PROOF, encoding="utf-8")
        (root / "proofs" / "main.zig").write_text('//! launcher, ignored\nconst Astra = 1;\n', encoding="utf-8")
        (root / "src" / "engine.zig").write_text(engine_source, encoding="utf-8")
        if baseline is not None:
            (root / sep.BASELINE_NAME).write_text(json.dumps({"counts": baseline}), encoding="utf-8")
        self.addCleanup(tmp.cleanup)
        return root

    def test_names_come_from_declarations_drafts_and_lookups(self):
        root = self.make_repo("")
        names = sep.load_proofs(root)["moon"]
        self.assertTrue({"Moon Base", "Astra", "Rover", "Airlock", "Hangar", "DockMark", "Lift", "Drop", "Beacon"} <= names)
        self.assertNotIn("Cat", names)      # shorter than MIN_NAME_LENGTH
        self.assertNotIn("Player", names)   # generic engine vocabulary
        self.assertNotIn("main", sep.load_proofs(root))

    def test_test_blocks_are_ignored_even_with_braces_in_strings(self):
        engine = (
            'pub fn ok() void {}\n'
            'test "fixtures may use proof names" {\n'
            '    const s = "} Astra {";\n'
            '    const m =\n'
            '        \\\\ } Rover\n'
            '    ;\n'
            '    _ = .{ s, m, "Airlock" };\n'
            '}\n'
            '// Hangar after the test block counts\n'
        )
        root = self.make_repo(engine)
        counts, hits = sep.scan(root)
        self.assertEqual(counts, {"src/engine.zig": {"moon": 1}})
        self.assertEqual(hits[0][:2], ("src/engine.zig", 9))

    def test_word_boundaries_avoid_partial_matches(self):
        root = self.make_repo('const AstraLike = 1; // Astras\nconst x = "Astra";\n')
        counts, _ = sep.scan(root)
        self.assertEqual(counts, {"src/engine.zig": {"moon": 1}})

    def test_new_leak_above_baseline_is_an_error(self):
        root = self.make_repo('const a = "Astra"; const b = "Rover";\n', baseline={"src/engine.zig": {"moon": 1}})
        errors, notes = sep.check(root)
        self.assertEqual(len(errors), 1)
        self.assertIn("baseline 1", errors[0])
        self.assertEqual(notes, [])

    def test_fewer_hits_than_baseline_is_a_note(self):
        root = self.make_repo('const a = "Astra";\n', baseline={"src/engine.zig": {"moon": 3}})
        errors, notes = sep.check(root)
        self.assertEqual(errors, [])
        self.assertEqual(len(notes), 1)

    def test_baseline_only_shrinks_without_accept_increase(self):
        root = self.make_repo('const a = "Astra"; const b = "Rover";\n', baseline={"src/engine.zig": {"moon": 1}})
        counts, _ = sep.scan(root)
        with redirect_stdout(io.StringIO()):
            self.assertEqual(sep.write_baseline(root, counts, accept_increase=False), 1)
        self.assertEqual(sep.load_baseline(root), {"src/engine.zig": {"moon": 1}})
        with redirect_stdout(io.StringIO()):
            self.assertEqual(sep.write_baseline(root, counts, accept_increase=True), 0)
        self.assertEqual(sep.load_baseline(root), {"src/engine.zig": {"moon": 2}})

    def test_zero_counts_are_dropped_from_the_baseline(self):
        root = self.make_repo("pub fn clean() void {}\n", baseline={"src/engine.zig": {"moon": 4}})
        counts, _ = sep.scan(root)
        with redirect_stdout(io.StringIO()):
            sep.write_baseline(root, counts, accept_increase=False)
        self.assertEqual(sep.load_baseline(root), {})

    def test_repository_matches_its_committed_baseline(self):
        errors, _ = sep.check(ROOT)
        self.assertEqual(errors, [])


if __name__ == "__main__":
    unittest.main()
