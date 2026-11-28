"""The Studio's examples stay true to the demos they copy (P50-02, P50-03, D-213)."""

import glob
import importlib.util
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("build_examples", ROOT / "tools" / "build_examples.py")
examples = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(examples)

# Hooks that only draw a HUD or solve the demo on a key; the game plays the same without them.
NOT_GAMEPLAY = {"catalyst", "status_hook"}
GAMEPLAY = ("setup", "after_tick", "on_act", "on_action", "on_typed", "on_choice", "exits")


def deck_hooks() -> dict[str, list[str]]:
    deck = (ROOT / "proofs" / "wasm_deck.zig").read_text(encoding="utf-8")
    out = {}
    for m in re.finditer(r'wasm\.script_deck_with\("([^"]+)", [\w.]+, \.\{(.*?)\n    \}\)', deck, re.S):
        out[m.group(1)] = [h for h in GAMEPLAY if re.search(r"\." + h + r"\s*=", m.group(2))]
    return out


class ExampleTests(unittest.TestCase):
    def test_each_proof_example_names_the_hooks_its_deck_runs(self):
        hooks = deck_hooks()
        for ex in examples.manifest():
            if "deck" not in ex:
                continue
            with self.subTest(example=ex["id"]):
                self.assertIn(ex["deck"], hooks)
                self.assertEqual(sorted(ex["host"]), sorted(hooks[ex["deck"]]))

    def test_every_deck_and_proof_script_is_an_example(self):
        listed = {ex.get("deck") for ex in examples.manifest()}
        self.assertEqual(set(deck_hooks()) - listed, set())
        mains = {(ROOT / ex["root"] / ex["main"]).resolve() for ex in examples.manifest()}
        for script in (ROOT / "proofs" / "scripts").glob("*.bespoke"):
            self.assertIn(script.resolve(), mains)

    def test_every_snapshot_is_a_build_input_and_every_scene_has_one(self):
        build = (ROOT / "build.zig").read_text(encoding="utf-8")
        listed = re.findall(r'^    "(proofs/scripts/art/[^"]+\.png)",$', build, re.M)
        self.assertEqual(listed, sorted(glob.glob("proofs/scripts/art/*/*.png", root_dir=ROOT)))
        for ex in examples.manifest():
            proof = ex.get("snapshots")
            if not proof:
                continue
            script = (ROOT / ex["root"] / ex["main"]).read_text(encoding="utf-8")
            text, art = examples.with_backdrops(script, proof)
            self.assertEqual(len(art), len(list((examples.SNAPSHOTS / proof).glob("*.png"))), proof)
            for path, _ in art:
                self.assertIn(f'from "{path}"', text)

    def test_the_bundle_is_stable(self):
        self.assertEqual(examples.bundle(), examples.bundle())

    def test_every_example_compiles(self):
        cli = ROOT / "zig-out" / "bin" / "bespoke"
        if not cli.exists():
            self.skipTest("run `zig build` first")
        self.assertEqual(examples.check(cli), 0)


if __name__ == "__main__":
    unittest.main()
