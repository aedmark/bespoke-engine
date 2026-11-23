#!/usr/bin/env python3
"""Run the language conformance suite (P48-18, D-173).

    zig build test-conformance
    python3 tools/check_conformance.py --bespoke zig-out/bin/bespoke [case ...]

Each case is a `.bespoke` file under tests/conformance/<rule>/ whose header comments say what it
pins and what the stock CLI must report. Directives, one per comment line:

    # pins: D-160; script_spec.md "Several handlers may share a signature"
    # ticks: 6                       headless ticks to run (default 4)
    # input: 0 use lamp              typed for the player after that many ticks
    # seed: 9                        the run's seed (default 42, D-184)
    # expect fact: Dry(Scout)        a final fact, as `bespoke run --facts` prints it
    # expect no fact: Burning(Scout)
    # expect line: Scout: "Hello"    some output line contains this text
    # expect error: UnboundVariable 3:24

A case with `expect error` must fail `bespoke check --kind` with that kind at that line and
column; the message wording is not part of the promise. Any other case must pass `bespoke
check` and is then run headless. Every case must name at least one decision in `pins`.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SUITE = ROOT / "tests" / "conformance"
DIRECTIVE = re.compile(r"^#\s*(pins|ticks|input|seed|expect fact|expect no fact|expect line|expect error):\s*(.*?)\s*$")
ERROR_AT = re.compile(r"^(\w+)\s+(\d+):(\d+)$")
DIAGNOSTIC = re.compile(r":(\d+):(\d+): error: ")


@dataclass
class Case:
    path: Path
    pins: list[str] = field(default_factory=list)
    ticks: int = 4
    seed: int | None = None
    inputs: list[str] = field(default_factory=list)
    facts: list[str] = field(default_factory=list)
    no_facts: list[str] = field(default_factory=list)
    lines: list[str] = field(default_factory=list)
    error: tuple[str, int, int] | None = None


def parse_case(path: Path) -> Case:
    case = Case(path)
    for raw in path.read_text(encoding="utf-8").splitlines():
        match = DIRECTIVE.match(raw.strip())
        if not match:
            continue
        key, value = match.groups()
        if key == "pins":
            case.pins.extend(part.strip() for part in value.split(";") if part.strip())
        elif key == "ticks":
            case.ticks = int(value)
        elif key == "input":
            case.inputs.append(value)
        elif key == "seed":
            case.seed = int(value)
        elif key == "expect fact":
            case.facts.append(value)
        elif key == "expect no fact":
            case.no_facts.append(value)
        elif key == "expect line":
            case.lines.append(value)
        elif key == "expect error":
            at = ERROR_AT.match(value)
            if not at:
                raise ValueError(f"{path}: `expect error` needs `<Kind> <line>:<column>`, found {value!r}")
            case.error = (at.group(1), int(at.group(2)), int(at.group(3)))
    if not any(re.match(r"D-\d{3}", pin) for pin in case.pins):
        raise ValueError(f"{path}: `pins` must name at least one decision (D-NNN)")
    if case.error and (case.facts or case.no_facts or case.inputs):
        raise ValueError(f"{path}: an `expect error` case cannot also run")
    return case


def run(bespoke: Path, args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run([str(bespoke), *args], capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=60)


def final_facts(output: str) -> set[str]:
    facts: set[str] = set()
    inside = False
    for line in output.splitlines():
        if line.startswith("facts: "):
            inside = True
        elif inside and line.startswith("fact "):
            facts.add(line[len("fact "):])
        elif inside:
            break
    return facts


def check_case(bespoke: Path, case: Case) -> list[str]:
    """The case's failures; empty when it conforms."""
    if case.error:
        kind, line, column = case.error
        result = run(bespoke, ["check", str(case.path), "--kind"])
        if result.returncode == 0:
            return [f"expected {kind} at {line}:{column}, but the script checked clean"]
        found_kind = next((l[len("kind: "):] for l in result.stdout.splitlines() if l.startswith("kind: ")), "?")
        where = DIAGNOSTIC.search(result.stdout)
        found_at = (int(where.group(1)), int(where.group(2))) if where else None
        if (found_kind, found_at) != (kind, (line, column)):
            at = f"{found_at[0]}:{found_at[1]}" if found_at else "?"
            return [f"expected {kind} at {line}:{column}, found {found_kind} at {at}"]
        return []

    checked = run(bespoke, ["check", str(case.path)])
    if checked.returncode != 0:
        return ["the script failed `bespoke check`:\n" + checked.stdout.strip()]
    with tempfile.NamedTemporaryFile("w", suffix=".in", delete=False, encoding="utf-8") as handle:
        handle.write("\n".join(case.inputs) + "\n")
        input_path = handle.name
    try:
        seed = ["--seed", str(case.seed)] if case.seed is not None else []
        result = run(bespoke, ["run", str(case.path), "--headless", "--ticks", str(case.ticks), "--input", input_path, "--facts", *seed])
    finally:
        Path(input_path).unlink(missing_ok=True)
    if result.returncode != 0:
        return [f"`bespoke run` exited {result.returncode}:\n" + (result.stdout + result.stderr).strip()[-800:]]
    facts = final_facts(result.stdout)
    problems = [f"missing fact {fact}" for fact in case.facts if fact not in facts]
    problems += [f"unexpected fact {fact}" for fact in case.no_facts if fact in facts]
    problems += [f"no output line contains {text!r}" for text in case.lines if not any(text in l for l in result.stdout.splitlines())]
    return problems


def discover(paths: list[str]) -> list[Path]:
    if paths:
        return [Path(p).resolve() for p in paths]
    return sorted(SUITE.rglob("*.bespoke"))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--bespoke", type=Path, default=ROOT / "zig-out" / "bin" / "bespoke", help="the CLI to test")
    parser.add_argument("cases", nargs="*", help="case files (default: every case under tests/conformance)")
    args = parser.parse_args(argv)
    if not args.bespoke.exists():
        print(f"{args.bespoke} not found; run `zig build` first", file=sys.stderr)
        return 2

    failed = 0
    cases = discover(args.cases)
    for path in cases:
        label = path.relative_to(ROOT) if path.is_relative_to(ROOT) else path
        try:
            problems = check_case(args.bespoke, parse_case(path))
        except ValueError as exc:
            problems = [str(exc)]
        if problems:
            failed += 1
            print(f"FAIL {label}")
            for problem in problems:
                print("     " + problem.replace("\n", "\n     "))
        else:
            print(f"ok   {label}")
    print(f"{len(cases) - failed} of {len(cases)} conformance cases pass")
    return 1 if failed or not cases else 0


if __name__ == "__main__":
    raise SystemExit(main())
