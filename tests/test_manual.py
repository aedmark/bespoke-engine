import contextlib
import copy
import importlib.util
import io
import json
import tempfile
import unittest
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("manual", ROOT / "tools" / "manual.py")
manual = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(manual)

REVIEW_DAY = date(2026, 11, 4)


class ManualTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.example = json.loads((ROOT / "scheme" / "example.manual.json").read_text(encoding="utf-8"))

    def test_example_validates_and_builds(self):
        expanded = manual.expand_placeholders(copy.deepcopy(self.example), self.example)
        errors, warnings = manual.validate(expanded, today=REVIEW_DAY)
        self.assertEqual(errors, [])
        self.assertEqual(warnings, [])
        output = manual.build_html(expanded)
        self.assertIn("Orbit Notes Manual", output)
        self.assertIn("tests/offline-edit.spec.ts", output)
        self.assertIn("What it does", output)
        self.assertIn("basis-observed", output)
        self.assertIn('class="reviewed"', output)

    def test_public_manual_sources_validate(self):
        for filename in ("3x.manual.json", "reference.manual.json"):
            source = json.loads((ROOT / "scheme" / filename).read_text(encoding="utf-8"))
            expanded = manual.expand_placeholders(copy.deepcopy(source), source)
            errors, warnings = manual.validate(expanded, today=REVIEW_DAY)
            self.assertEqual(errors, [], filename)
            self.assertEqual(warnings, [], filename)

    def test_schema_and_validator_agree_on_core_contract(self):
        schema = json.loads((ROOT / "scheme" / "manual.schema.json").read_text(encoding="utf-8"))
        self.assertEqual(set(schema["properties"]), manual.ALLOWED_ROOT)
        self.assertFalse(schema["additionalProperties"])
        self.assertEqual(set(schema["properties"]["project"]["properties"]), manual.ALLOWED_PROJECT)
        self.assertEqual(set(schema["properties"]["project"]["required"]), {"name", "version"})
        self.assertEqual(set(schema["properties"]["manual"]["properties"]), manual.ALLOWED_MANUAL)
        self.assertEqual(set(schema["properties"]["manual"]["required"]), {"title"})
        self.assertFalse(schema["properties"]["manual"]["additionalProperties"])
        self.assertEqual(set(schema["properties"]["theme"]["properties"]), manual.ALLOWED_THEME)
        self.assertFalse(schema["properties"]["theme"]["additionalProperties"])
        entry = schema["$defs"]["entry"]
        self.assertEqual(set(entry["properties"]), manual.ALLOWED_ENTRY)
        self.assertEqual(
            set(entry["required"]),
            {"id", "title", "what", "how", "why", "why_basis"},
        )
        self.assertFalse(entry["additionalProperties"])
        self.assertEqual(set(schema["$defs"]["why_basis"]["enum"]), set(manual.BASIS_VALUES))
        self.assertEqual(
            set(schema["$defs"]["evidence_kind"]["enum"]),
            set(manual.EVIDENCE_KINDS),
        )
        self.assertEqual(
            set(schema["$defs"]["evidence"]["oneOf"][1]["properties"]),
            manual.ALLOWED_EVIDENCE,
        )
        reviewed = schema["$defs"]["reviewed"]
        self.assertEqual(set(reviewed["properties"]), manual.ALLOWED_REVIEWED)
        self.assertEqual(set(reviewed["required"]), {"date", "commit"})
        self.assertFalse(reviewed["additionalProperties"])

    def test_why_basis_is_required_and_validated(self):
        data = copy.deepcopy(self.example)
        del data["sections"][0]["entries"][0]["why_basis"]
        errors, _ = manual.validate(data, today=REVIEW_DAY)
        self.assertTrue(any("why_basis" in error for error in errors))

        data = copy.deepcopy(self.example)
        data["sections"][0]["entries"][0]["why_basis"] = "guess"
        errors, _ = manual.validate(data, today=REVIEW_DAY)
        self.assertTrue(any("why_basis" in error for error in errors))

    def test_recorded_basis_with_inferred_wording_warns(self):
        data = copy.deepcopy(self.example)
        entry = data["sections"][0]["entries"][0]
        entry["why_basis"] = "recorded"
        entry["why"] = "Inferred from the shape of the write path."
        errors, warnings = manual.validate(data, today=REVIEW_DAY)
        self.assertEqual(errors, [])
        self.assertTrue(any("conflicts with inferred" in warning for warning in warnings))

    def test_reviewed_is_validated_and_stale_reviews_warn(self):
        data = copy.deepcopy(self.example)
        del data["manual"]["reviewed"]
        errors, warnings = manual.validate(data, today=REVIEW_DAY)
        self.assertEqual(errors, [])
        self.assertTrue(any("missing review" in warning for warning in warnings))

        data = copy.deepcopy(self.example)
        data["manual"]["reviewed"]["date"] = "2020-01-01"
        data["manual"]["reviewed"]["interval_days"] = 180
        _, warnings = manual.validate(data, today=REVIEW_DAY)
        self.assertTrue(any("last review was" in warning for warning in warnings))

        data = copy.deepcopy(self.example)
        data["manual"]["reviewed"]["date"] = "2026-02-30"
        errors, _ = manual.validate(data, today=REVIEW_DAY)
        self.assertTrue(any("expected YYYY-MM-DD" in error for error in errors))

    def test_evidence_kind_is_validated(self):
        data = copy.deepcopy(self.example)
        data["sections"][0]["entries"][0]["evidence"][0]["kind"] = "guess"
        errors, _ = manual.validate(data, today=REVIEW_DAY)
        self.assertTrue(any("kind" in error for error in errors))

    def test_check_evidence_finds_missing_and_rejects_outside_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            data = copy.deepcopy(self.example)
            for entry in data["sections"][0]["entries"]:
                entry["evidence"] = [
                    {"label": "Missing", "target": "missing.ts", "kind": "source"}
                ]
            _, warnings = manual.validate(
                data,
                check_evidence=True,
                root=Path(directory),
                today=REVIEW_DAY,
            )
            self.assertTrue(any("not found" in warning for warning in warnings))

            data = copy.deepcopy(self.example)
            for entry in data["sections"][0]["entries"]:
                entry["evidence"] = [
                    {"label": "Outside", "target": "../outside.ts", "kind": "source"}
                ]
            _, warnings = manual.validate(
                data,
                check_evidence=True,
                root=Path(directory) / "project",
                today=REVIEW_DAY,
            )
            self.assertTrue(any("outside the evidence root" in warning for warning in warnings))

    def test_check_evidence_accepts_existing_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "exists.ts").write_text("ok", encoding="utf-8")
            data = copy.deepcopy(self.example)
            for entry in data["sections"][0]["entries"]:
                entry["evidence"] = [
                    {"label": "Exists", "target": "exists.ts", "kind": "source"}
                ]
            errors, warnings = manual.validate(
                data,
                check_evidence=True,
                root=root,
                today=REVIEW_DAY,
            )
            self.assertEqual(errors, [])
            self.assertFalse(any("evidence target" in warning for warning in warnings))

    def test_check_urls_warns_on_unreachable_targets(self):
        data = copy.deepcopy(self.example)
        data["sections"][0]["entries"][0]["evidence"] = [
            {"label": "Unreachable", "target": "http://127.0.0.1:1/", "kind": "url"}
        ]
        errors, warnings = manual.validate(
            data,
            check_urls=True,
            url_timeout=0.1,
            today=REVIEW_DAY,
        )
        self.assertEqual(errors, [])
        self.assertTrue(any("URL check failed" in warning for warning in warnings))

    def test_safe_relative_links_render(self):
        self.assertIn('href="commands.html"', manual.inline("[Reference](commands.html)"))
        self.assertNotIn("href=", manual.inline("[Unsafe](javascript:alert(1))"))

    def test_duplicate_ids_are_errors(self):
        data = copy.deepcopy(self.example)
        data["sections"][0]["entries"][1]["id"] = "local-notebooks"
        errors, _ = manual.validate(data, today=REVIEW_DAY)
        self.assertTrue(any("duplicate ID" in error for error in errors))

    def test_unknown_related_id_is_a_warning(self):
        data = copy.deepcopy(self.example)
        data["sections"][0]["entries"][0]["related"] = ["missing-entry"]
        errors, warnings = manual.validate(data, today=REVIEW_DAY)
        self.assertEqual(errors, [])
        self.assertTrue(any("unknown ID" in warning for warning in warnings))

    def test_todo_is_an_error(self):
        errors, _ = manual.validate(manual.starter("Example"), today=REVIEW_DAY)
        self.assertTrue(any("placeholder text" in error for error in errors))

    def test_starter_includes_provenance_and_evidence_kind(self):
        entry = manual.starter("Example")["sections"][0]["entries"][0]
        self.assertEqual(entry["why_basis"], "inferred")
        self.assertEqual(entry["evidence"][0]["kind"], "source")

    def test_overrides_and_placeholders(self):
        data = copy.deepcopy(self.example)
        manual.apply_override(data, "project.version=3.5.0")
        expanded = manual.expand_placeholders(data, copy.deepcopy(data))
        self.assertEqual(expanded["manual"]["badges"][0], "Release 3.5.0")

    def test_build_command_writes_file(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "nested" / "manual.html"
            result = manual.run_build(ROOT / "scheme" / "example.manual.json", output, [])
            self.assertEqual(result, 0)
            self.assertTrue(output.is_file())

    def test_build_check_detects_missing_and_drifted_output(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "manual.html"
            self.assertEqual(
                manual.run_build(ROOT / "scheme" / "example.manual.json", output, []),
                0,
            )
            self.assertEqual(
                manual.run_build(
                    ROOT / "scheme" / "example.manual.json",
                    output,
                    [],
                    check=True,
                ),
                0,
            )
            output.write_text(output.read_text(encoding="utf-8") + "drift", encoding="utf-8")
            self.assertEqual(
                manual.run_build(
                    ROOT / "scheme" / "example.manual.json",
                    output,
                    [],
                    check=True,
                ),
                1,
            )
            missing = Path(directory) / "missing.html"
            self.assertEqual(
                manual.run_build(
                    ROOT / "scheme" / "example.manual.json",
                    missing,
                    [],
                    check=True,
                ),
                1,
            )
            self.assertFalse(missing.exists())

    def test_lint_clean_example(self):
        expanded = manual.expand_placeholders(copy.deepcopy(self.example), self.example)
        self.assertEqual(manual.lint(expanded), [])

    def test_lint_flags_em_dash_without_blocking_check(self):
        data = copy.deepcopy(self.example)
        data["sections"][0]["entries"][0]["why"] = "Fast \u2014 and careful."
        errors, _ = manual.validate(data, today=REVIEW_DAY)
        self.assertEqual(errors, [])
        findings = manual.lint(data)
        self.assertTrue(any("em dash" in finding for finding in findings))

    def test_lint_flags_invisible_and_seesaw(self):
        data = copy.deepcopy(self.example)
        data["sections"][0]["entries"][0]["what"] = "It\u200b works."
        data["sections"][0]["entries"][1]["why"] = "It's not fast, it's careful."
        findings = manual.lint(data)
        self.assertTrue(any("U+200B" in finding for finding in findings))
        self.assertTrue(any("seesaw" in finding for finding in findings))

    def test_lint_rule_ids_are_stable(self):
        data = copy.deepcopy(self.example)
        data["sections"][0]["entries"][0]["what"] = "It\u200b works."
        data["sections"][0]["entries"][0]["why"] = "Fast \u2014 careful."
        data["sections"][0]["entries"][1]["why"] = "It's not fast, it's careful."
        findings = manual.lint_findings(data)
        rules = {finding["rule"] for finding in findings}
        self.assertTrue({"L001", "L002", "L004"}.issubset(rules))

    def test_lint_skips_literal_synopsis(self):
        data = copy.deepcopy(self.example)
        data["sections"][0]["entries"][1]["synopsis"] = "run \u2014 now"
        self.assertEqual(manual.lint(data), [])

    def test_lint_command_returns_one_for_style(self):
        data = json.loads((ROOT / "scheme" / "example.manual.json").read_text(encoding="utf-8"))
        data["sections"][0]["entries"][0]["why"] = "Fast \u2014 careful."
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "style.manual.json"
            source.write_text(json.dumps(data), encoding="utf-8")
            self.assertEqual(manual.run_lint(source, []), 1)

    def test_lint_command_passes_clean_example(self):
        self.assertEqual(manual.run_lint(ROOT / "scheme" / "example.manual.json", []), 0)

    def test_review_reports_inferred_items_and_strict_mode(self):
        data = copy.deepcopy(self.example)
        errors, warnings, items = manual.review(data, today=REVIEW_DAY)
        self.assertEqual(errors, [])
        self.assertFalse(any("conflicts" in warning for warning in warnings))
        self.assertTrue(any(item["kind"] == "inferred-rationale" for item in items))
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "review.manual.json"
            source.write_text(json.dumps(data), encoding="utf-8")
            self.assertEqual(manual.run_review(source, [], strict=False), 0)
            self.assertEqual(manual.run_review(source, [], strict=True), 1)

    def test_json_output_for_check_and_lint(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "example.manual.json"
            source.write_text(json.dumps(self.example), encoding="utf-8")
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                self.assertEqual(manual.run_check(source, [], json_output=True), 0)
            payload = json.loads(output.getvalue())
            self.assertEqual(payload["command"], "check")
            self.assertTrue(payload["passed"])
            self.assertEqual(payload["errors"], [])

            data = copy.deepcopy(self.example)
            data["sections"][0]["entries"][0]["why"] = "Fast \u2014 careful."
            source.write_text(json.dumps(data), encoding="utf-8")
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                self.assertEqual(manual.run_lint(source, [], json_output=True), 1)
            payload = json.loads(output.getvalue())
            self.assertEqual(payload["command"], "lint")
            self.assertFalse(payload["passed"])
            self.assertEqual(payload["findings"][0]["rule"], "L001")

    def test_review_reports_each_item_kind(self):
        data = copy.deepcopy(self.example)
        del data["manual"]["reviewed"]
        _, _, items = manual.review(data, today=REVIEW_DAY)
        self.assertTrue(any(item["kind"] == "unreviewed" for item in items))

        data = copy.deepcopy(self.example)
        data["manual"]["reviewed"]["date"] = "2020-01-01"
        data["manual"]["reviewed"]["interval_days"] = 180
        _, _, items = manual.review(data, today=REVIEW_DAY)
        self.assertTrue(any(item["kind"] == "stale-review" for item in items))

        data = copy.deepcopy(self.example)
        data["sections"][0]["entries"][0]["evidence"] = []
        _, _, items = manual.review(data, today=REVIEW_DAY)
        self.assertTrue(any(item["kind"] == "missing-evidence" for item in items))

        data = copy.deepcopy(self.example)
        data["sections"][0]["entries"][0]["evidence"] = [
            {
                "label": "Conflict policy decision",
                "target": "docs/decisions/0004-conflict-policy.md",
                "kind": "decision",
            }
        ]
        errors, _, items = manual.review(data, today=REVIEW_DAY)
        self.assertEqual(errors, [])
        self.assertTrue(any(item["kind"] == "weak-evidence" for item in items))

    def test_manual_does_not_embed_simulator(self):
        data = copy.deepcopy(self.example)
        data["sections"][0]["entries"][0]["id"] = "wasm-browser-target-and-simulator"
        rendered = manual.build_html(data)
        self.assertNotIn("live-simulator", rendered)
        self.assertNotIn("WebAssembly.instantiate", rendered)
        self.assertNotIn("bespoke-proofs.wasm", rendered)

    def test_json_output_for_review(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "review.manual.json"
            source.write_text(json.dumps(self.example), encoding="utf-8")
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                self.assertEqual(
                    manual.run_review(source, [], strict=True, json_output=True),
                    1,
                )
            payload = json.loads(output.getvalue())
            self.assertEqual(payload["command"], "review")
            self.assertTrue(payload["items"])
            self.assertFalse(payload["passed"])


if __name__ == "__main__":
    unittest.main()
