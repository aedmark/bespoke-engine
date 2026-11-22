"""P48-18: the conformance runner reads its directives and refuses malformed cases."""
from pathlib import Path
import tempfile
import unittest

from tools.check_conformance import final_facts, parse_case


def case(text: str) -> Path:
    handle = tempfile.NamedTemporaryFile("w", suffix=".bespoke", delete=False, encoding="utf-8")
    handle.write(text)
    handle.close()
    return Path(handle.name)


class ConformanceRunnerTests(unittest.TestCase):
    def test_directives_are_read(self):
        path = case("# pins: D-160; spec\n# ticks: 6\n# input: 0 use lamp\n# expect fact: Dry(Scout)\n# expect no fact: Wet(Scout)\n# expect line: Scout: \"Hi\"\nentity Scout\n")
        self.addCleanup(path.unlink)
        parsed = parse_case(path)
        self.assertEqual((parsed.pins, parsed.ticks, parsed.inputs), (["D-160", "spec"], 6, ["0 use lamp"]))
        self.assertEqual((parsed.facts, parsed.no_facts, parsed.lines), (["Dry(Scout)"], ["Wet(Scout)"], ['Scout: "Hi"']))

    def test_a_case_must_pin_a_decision(self):
        path = case("# pins: script_spec.md\nentity Scout\n")
        self.addCleanup(path.unlink)
        with self.assertRaises(ValueError):
            parse_case(path)

    def test_an_error_case_cannot_also_run(self):
        path = case("# pins: D-161\n# expect error: UnboundVariable 3:4\n# input: 0 look\n")
        self.addCleanup(path.unlink)
        with self.assertRaises(ValueError):
            parse_case(path)

    def test_final_facts_stop_at_the_end_of_the_list(self):
        output = "facts: 2\nfact Lit(Lamp)\nfact Dry(Scout)\n\nfact Ignored(Later)\n"
        self.assertEqual(final_facts(output), {"Lit(Lamp)", "Dry(Scout)"})


if __name__ == "__main__":
    unittest.main()
