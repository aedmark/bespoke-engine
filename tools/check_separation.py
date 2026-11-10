#!/usr/bin/env python3
"""Separation lint: keep proof-of-concept content out of engine code (P32-06, D-031).

Every proof in proofs/ declares names in its embedded BeSpoke script (scene, cast, props,
marks, entity, and draft declarations) and in `lookup_entity("...")` literals. This tool counts
occurrences of those names in non-test engine code under src/ and compares the counts with a
committed baseline, tools/separation_baseline.json.

  * A count above baseline is an error: new proof content leaked into the engine.
  * A count below baseline is a note: lower the baseline with --update-baseline.
  * The baseline only shrinks. Raising it needs --accept-increase, a deliberate, reviewed act.

Comments count. A comment naming a proof's character misleads readers of engine code as much
as a branch on it does. Test blocks do not count: engine tests may use any fixture names.

Usage:
  python3 tools/check_separation.py                    # check against the baseline
  python3 tools/check_separation.py --report           # list every hit with file:line
  python3 tools/check_separation.py --update-baseline  # record lower counts
  python3 tools/check_separation.py --update-baseline --accept-increase

Standard library only, like the other tools.
"""
import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASELINE_NAME = "tools/separation_baseline.json"

# Names shorter than this are too ambiguous to lint (e.g. "Cat", "Bar").
MIN_NAME_LENGTH = 4

# Words a proof declares that are also generic engine vocabulary. Each entry hides real leaks
# if misused, so every one needs a reason. Keep this list short.
GENERIC_NAMES = {
    "Player": "default actor name in the engine runner and REPL",
    "Scene": "default animation target in the compiler",
}

DECL_RE = re.compile(r"^\s*(?:scene|cast|props|marks|entity)\b\s*:?\s*(.+)$", re.M)
DRAFT_RE = re.compile(r"^\s*draft\s+(\w+)\s*\([^)]*\)(?:\s+reverse\s+(\w+))?", re.M)
LOOKUP_RE = re.compile(r'lookup_entity\("([^"]+)"\)')
TEST_START_RE = re.compile(r'^test\s+"')


def script_text(zig_source):
    """Joins the lines of every Zig multiline string literal (the embedded DSL scripts)."""
    out = []
    for line in zig_source.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("\\\\"):
            out.append(stripped[2:])
    return "\n".join(out)


def proof_names(proof_file):
    """Returns the set of names a proof declares."""
    source = proof_file.read_text(encoding="utf-8")
    script = script_text(source)
    names = set()
    for m in DECL_RE.finditer(script):
        for part in re.split(r"[,|]", m.group(1)):
            name = part.split(":")[0].strip().rstrip(".")
            if name:
                names.add(name)
    for m in DRAFT_RE.finditer(script):
        names.update(g for g in m.groups() if g)
    names.update(LOOKUP_RE.findall(source))
    return {
        n for n in names
        if len(n) >= MIN_NAME_LENGTH and n[0].isupper() and n not in GENERIC_NAMES
    }


# Files in proofs/ that are not proofs. main.zig is the launcher; art.zig is the presentation the
# proofs share (D-039), and every name it uses belongs to a proof script already, so counting it
# would count the same leak twice.
NOT_PROOFS = {"main.zig", "art.zig"}


def load_proofs(root):
    proofs = {}
    for f in sorted((root / "proofs").glob("*.zig")):
        if f.name in NOT_PROOFS:
            continue
        names = proof_names(f)
        if names:
            proofs[f.stem] = names
    return proofs


def strip_test_blocks(source):
    """Blanks out top-level `test "..." { ... }` blocks, keeping line numbers stable.

    Braces are matched while skipping string and character literals, `//` comments, and
    multiline string lines (`\\\\`), so braces inside test strings cannot end a block early.
    """
    lines = source.splitlines()
    keep = [True] * len(lines)
    i = 0
    while i < len(lines):
        if not TEST_START_RE.match(lines[i]):
            i += 1
            continue
        depth = 0
        opened = False
        j = i
        while j < len(lines):
            keep[j] = False
            line = lines[j]
            if line.lstrip().startswith("\\\\"):
                j += 1
                continue
            k = 0
            while k < len(line):
                ch = line[k]
                if ch == "/" and line[k:k + 2] == "//":
                    break
                if ch in "\"'":
                    quote = ch
                    k += 1
                    while k < len(line) and line[k] != quote:
                        k += 2 if line[k] == "\\" else 1
                elif ch == "{":
                    depth += 1
                    opened = True
                elif ch == "}":
                    depth -= 1
                k += 1
            j += 1
            if opened and depth <= 0:
                break
        i = j
    return "\n".join(line if keep[n] else "" for n, line in enumerate(lines))


def name_pattern(name):
    return re.compile(r"(?<![A-Za-z0-9_])" + re.escape(name) + r"(?![A-Za-z0-9_])")


def scan(root):
    """Returns (counts, hits): counts[file][proof] = n, hits = [(file, line, proof, name)]."""
    proofs = load_proofs(root)
    patterns = {(p, n): name_pattern(n) for p, names in proofs.items() for n in names}
    counts = defaultdict(lambda: defaultdict(int))
    hits = []
    for f in sorted((root / "src").rglob("*.zig")):
        rel = f.relative_to(root).as_posix()
        body = strip_test_blocks(f.read_text(encoding="utf-8"))
        for lineno, line in enumerate(body.splitlines(), 1):
            for (proof, name), pat in patterns.items():
                n = len(pat.findall(line))
                if n:
                    counts[rel][proof] += n
                    hits.extend([(rel, lineno, proof, name)] * n)
    return {f: dict(p) for f, p in counts.items()}, hits


def load_baseline(root):
    path = root / BASELINE_NAME
    if not path.is_file():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    return data.get("counts", {})


def compare(counts, baseline):
    """Returns (errors, notes) comparing current counts with the baseline."""
    errors, notes = [], []
    keys = {(f, p) for f, ps in counts.items() for p in ps} | {(f, p) for f, ps in baseline.items() for p in ps}
    for f, p in sorted(keys):
        now = counts.get(f, {}).get(p, 0)
        base = baseline.get(f, {}).get(p, 0)
        if now > base:
            errors.append(f"{f}: {now} name(s) from proof '{p}' (baseline {base}); "
                          f"run `python3 tools/check_separation.py --report` to see them")
        elif now < base:
            notes.append(f"{f}: {now} name(s) from proof '{p}', below baseline {base}; "
                         f"lower it with --update-baseline")
    return errors, notes


def check(root=ROOT):
    """Entry point for tools/check_docs.py. Returns (errors, warnings)."""
    if not (root / "proofs").is_dir():
        return [], []
    counts, _ = scan(root)
    return compare(counts, load_baseline(root))


def write_baseline(root, counts, accept_increase):
    baseline = load_baseline(root)
    merged = {}
    raised = []
    for f in sorted(set(counts) | set(baseline)):
        for p in sorted(set(counts.get(f, {})) | set(baseline.get(f, {}))):
            now = counts.get(f, {}).get(p, 0)
            base = baseline.get(f, {}).get(p)
            # A file or proof the baseline has never seen counts as 0: a new leak is an increase too.
            if now > (base or 0) and not accept_increase:
                raised.append(f"{f} [{p}]: {base or 0} -> {now}")
                now = base or 0
            if now:
                merged.setdefault(f, {})[p] = now
    if raised:
        print("refusing to raise the baseline without --accept-increase:")
        for r in raised:
            print(f"  {r}")
    doc = {
        "about": "Proof names allowed in non-test src/ code. Only shrinks; see tools/check_separation.py (P32-06).",
        "total": sum(sum(p.values()) for p in merged.values()),
        "counts": merged,
    }
    (root / BASELINE_NAME).write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 1 if raised else 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--report", action="store_true", help="list every hit with file:line")
    ap.add_argument("--update-baseline", action="store_true", help="record current counts (lower only)")
    ap.add_argument("--accept-increase", action="store_true", help="with --update-baseline, allow raising counts")
    ap.add_argument("--root", type=Path, default=ROOT)
    args = ap.parse_args(argv)

    counts, hits = scan(args.root)
    if args.report:
        for f, line, proof, name in hits:
            print(f"{f}:{line}: [{proof}] {name}")
        print(f"{len(hits)} hit(s)")
    if args.update_baseline:
        return write_baseline(args.root, counts, args.accept_increase)

    errors, notes = compare(counts, load_baseline(args.root))
    for n in notes:
        print(f"NOTE  {n}")
    for e in errors:
        print(f"ERROR {e}")
    total = sum(sum(p.values()) for p in counts.values())
    print(f"{len(errors)} error(s); {total} proof name(s) in engine code")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
