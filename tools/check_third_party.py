#!/usr/bin/env python3
"""Third-party name lint: count borrowed titles, characters, places, and lines (P35-01, Q-005).

Several proofs borrow from commercial games and a film. Phase 35 rewrites each as an original.
This tool counts the terms in tools/third_party_terms.json across the code and public pages and
compares the counts with a committed baseline, tools/third_party_baseline.json:

  * A count above baseline is an error: a borrowed name or line came back or spread.
  * A count below baseline is a note: lower the baseline with --update-baseline.
  * The baseline only shrinks. Raising it needs --accept-increase, a deliberate, reviewed act.

Scanned: src/, proofs/ (goldens included), scenarios/, site/index.html (without the embedded
WebAssembly region), tools/site_gallery.json, scheme/, README.md, and docs/state.html.
Append-only history (DECISIONS, CHANGELOG, the archive, finished roadmap items) is not
scanned: it records what was true. docs/manual.html is built from scheme/, so it is not
counted twice.

Quoted lines are matched by digest: every double-quoted string of 12 or more characters is
lowercased, its whitespace collapsed, and its SHA-256 compared with the list. HTML tags and
JSON escapes are removed first, so a line inside the site's highlighted script viewer counts.

Usage:
  python3 tools/check_third_party.py                    # check against the baseline
  python3 tools/check_third_party.py --report           # list every hit with file:line
  python3 tools/check_third_party.py --update-baseline  # record lower counts
  python3 tools/check_third_party.py --update-baseline --accept-increase

Standard library only, like the other tools.
"""
import argparse
import hashlib
import html
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TERMS_NAME = "tools/third_party_terms.json"
BASELINE_NAME = "tools/third_party_baseline.json"

SCAN_DIRS = ("src", "proofs", "scenarios", "scheme")
SCAN_FILES = ("site/index.html", "tools/site_gallery.json", "README.md", "docs/state.html")
SCAN_SUFFIXES = {".zig", ".tmpl", ".bespoke", ".txt", ".json", ".html", ".md"}
# The site embeds the proofs' WebAssembly as base64; random letters must not count.
EMBED_START = "<!-- SITE_SIMULATOR_START -->"
EMBED_END = "<!-- SITE_SIMULATOR_END -->"

MIN_LINE_LENGTH = 12
QUOTED_RE = re.compile(r'"([^"\n]{%d,})"' % MIN_LINE_LENGTH)
TAG_RE = re.compile(r"<[^>]+>")


def load_terms(root):
    data = json.loads((root / TERMS_NAME).read_text(encoding="utf-8"))
    return data["sources"]


def name_pattern(name):
    # Not inside a longer word on the left; on the right, a lowercase letter or digit would
    # continue the word, while a capital (CamelCase) or underscore starts the next part.
    return re.compile(r"(?<![A-Za-z0-9])" + re.escape(name) + r"(?![a-z0-9])")


def normalise_line(text):
    return re.sub(r"\s+", " ", text.strip().lower())


def line_digest(text):
    return hashlib.sha256(normalise_line(text).encode("utf-8")).hexdigest()


def plain_text(text):
    """Text as a reader sees it: no wasm embed, no tags, no JSON or HTML escapes."""
    if EMBED_START in text and EMBED_END in text:
        start = text.index(EMBED_START)
        end = text.index(EMBED_END, start)
        # Keep the line count, so --report line numbers stay true.
        text = text[:start] + "\n" * text.count("\n", start, end) + text[end:]
    text = text.replace('\\"', '"').replace("\\/", "/")
    text = TAG_RE.sub("", text)
    return html.unescape(text)


def scan_targets(root):
    files = []
    for d in SCAN_DIRS:
        base = root / d
        if base.is_dir():
            files.extend(p for p in sorted(base.rglob("*")) if p.is_file() and p.suffix in SCAN_SUFFIXES)
    files.extend(root / f for f in SCAN_FILES if (root / f).is_file())
    return files


def scan(root):
    """Returns (counts, hits): counts[file][source] = n, hits = [(file, line, source, term)]."""
    sources = load_terms(root)
    names = [(s, n, name_pattern(n)) for s, spec in sources.items() for n in spec.get("names", [])]
    digests = {h: s for s, spec in sources.items() for h in spec.get("lines_sha256", [])}
    counts = defaultdict(lambda: defaultdict(int))
    hits = []
    terms_path = (root / TERMS_NAME).resolve()
    for f in scan_targets(root):
        if f.resolve() == terms_path:
            continue
        rel = f.relative_to(root).as_posix()
        text = plain_text(f.read_text(encoding="utf-8", errors="replace"))
        for lineno, line in enumerate(text.splitlines(), 1):
            for source, name, pat in names:
                n = len(pat.findall(line))
                if n:
                    counts[rel][source] += n
                    hits.extend([(rel, lineno, source, name)] * n)
            for m in QUOTED_RE.finditer(line):
                source = digests.get(line_digest(m.group(1)))
                if source:
                    counts[rel][source] += 1
                    hits.append((rel, lineno, source, "(quoted line)"))
    return {f: dict(s) for f, s in counts.items()}, hits


def load_baseline(root):
    path = root / BASELINE_NAME
    if not path.is_file():
        return {}
    return json.loads(path.read_text(encoding="utf-8")).get("counts", {})


def compare(counts, baseline):
    """Returns (errors, notes) comparing current counts with the baseline."""
    errors, notes = [], []
    keys = {(f, s) for f, ss in counts.items() for s in ss} | {(f, s) for f, ss in baseline.items() for s in ss}
    for f, s in sorted(keys):
        now = counts.get(f, {}).get(s, 0)
        base = baseline.get(f, {}).get(s, 0)
        if now > base:
            errors.append(f"{f}: {now} term(s) from {s} (baseline {base}); "
                          f"run `python3 tools/check_third_party.py --report` to see them")
        elif now < base:
            notes.append(f"{f}: {now} term(s) from {s}, below baseline {base}; "
                         f"lower it with `python3 tools/check_third_party.py --update-baseline`")
    return errors, notes


def check(root=ROOT):
    """Entry point for tools/check_docs.py. Returns (errors, warnings)."""
    if not (root / TERMS_NAME).is_file():
        return [], []
    counts, _ = scan(root)
    return compare(counts, load_baseline(root))


def write_baseline(root, counts, accept_increase):
    baseline = load_baseline(root)
    merged, raised = {}, []
    for f in sorted(set(counts) | set(baseline)):
        for s in sorted(set(counts.get(f, {})) | set(baseline.get(f, {}))):
            now = counts.get(f, {}).get(s, 0)
            base = baseline.get(f, {}).get(s)
            if base is not None and now > base and not accept_increase:
                now = base
                raised.append((f, s))
            if now:
                merged.setdefault(f, {})[s] = now
    data = {
        "about": "Third-party terms allowed today. Only shrinks; see tools/check_third_party.py (P35-01).",
        "counts": merged,
        "total": sum(n for ss in merged.values() for n in ss.values()),
    }
    (root / BASELINE_NAME).write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return raised


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--report", action="store_true", help="list every hit")
    parser.add_argument("--update-baseline", action="store_true", help="record lower counts")
    parser.add_argument("--accept-increase", action="store_true", help="with --update-baseline, also record higher counts")
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args(argv)
    counts, hits = scan(args.root)
    if args.report:
        for f, line, source, term in hits:
            print(f"{f}:{line}: {source}: {term}")
    if args.update_baseline:
        raised = write_baseline(args.root, counts, args.accept_increase)
        for f, s in raised:
            print(f"kept baseline for {f} ({s}): the count rose; pass --accept-increase to record it", file=sys.stderr)
        return 1 if raised else 0
    errors, notes = compare(counts, load_baseline(args.root))
    for e in errors:
        print(f"ERROR {e}")
    for n in notes:
        print(f"NOTE  {n}")
    total = sum(n for ss in counts.values() for n in ss.values())
    print(f"{total} third-party term(s) in {len(counts)} file(s); {len(errors)} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
