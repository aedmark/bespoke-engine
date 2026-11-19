#!/usr/bin/env python3
"""Check the project docs for the mistakes that make a handoff lie.

    python3 tools/check_docs.py              # from the repo root
    python3 tools/check_docs.py --template   # the template itself: placeholders are expected

Errors (exit 1):
  - a {{placeholder}} left in a doc
  - a roadmap ID used twice, filed under the wrong phase, or with an unknown checkbox
  - a decision number used twice or out of order, or superseded by one that does not exist or comes earlier
  - an open question (Q-NNN) defined twice
  - a held tension (T-NNN) used twice, out of order, or referenced but not defined
  - a roadmap ID, decision number, question or tension mentioned in a doc that does not exist
  - a band row quoted in prose that differs from the rows in src/display/band.zig (P43-07)
  - two session-log entries with the same number (HANDOFF and docs/archive/ together)
  - a relative link, or a path in AGENTS.md's Layout table, that points at nothing
  - an invisible or bidirectional control character in a document
Warnings (exit 0):
  - HANDOFF's "Last updated" is missing, or older than its newest session-log entry
  - HANDOFF's session log or "Current state" has outgrown the limits below (time to archive)

Standard library only. HTML comments are ignored, so examples can live in them.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = [
    "AGENTS.md", "CLAUDE.md", "README.md", "ROADMAP.md",
    "docs/README.md", "docs/ROADMAP.md", "docs/HANDOFF.md", "docs/ARCHITECTURE.md", "docs/DECISIONS.md",
    "docs/TESTING.md", "docs/SECURITY.md", "docs/CHANGELOG.md", "docs/CONTRIBUTING.md",
    "docs/SEPARATION.md", "docs/FIRST_GAME.md", "docs/BENCHMARKS.md", "editors/vscode/README.md",
]
# Keep in step with AGENTS.md (end of session, step 3) and HANDOFF's header.
LOG_LIMIT = 10
CURRENT_STATE_LINES = 80

ITEM_RE = re.compile(r"\bP(\d+)-(\d+)\b")
DECISION_RE = re.compile(r"\bD-(\d{3})\b")
QUESTION_RE = re.compile(r"\bQ-(\d{3})\b")
TENSION_RE = re.compile(r"\bT-(\d{3})\b")
INVISIBLE_RE = re.compile(r"[\u180e\u200b-\u200f\u202a-\u202e\u2060-\u206f\ufeff]")
DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}")
LINK_RE = re.compile(r"\]\(([^)\s]+)\)|\b(?:href|src)=\"([^\"]+)\"")

errors, warnings = [], []

# P43-07: the band's rows are written in one place, so a document that quotes them is checked
# against that source instead of against a copy. Each pattern captures the number it quotes.
BAND_TOP_PHRASES = (
    r"band's (?:tallest )?top of (\d+)",
    r"top of (\d+) with four rows",
    r"\((\d+) pixels at 1280x720\)",
    r"clears (\d+) only from world y \d+",
    r"paints row (\d+), the band's first row",
    r"marker ends? at (\d+)",
)
BAND_BOTTOM_PHRASES = (
    r"grows upward from (?:y )?(\d+)",
    r"from y (\d+) at 1280x720",
)
ROLLING_BAND_PAIR = re.compile(r"in rows (\d+) to (\d+)")


def band_rows(root):
    """The band's top and bottom rows at 1280x720, computed from src/display/band.zig (P43-07).

    The source is the one owner of the arithmetic, so the checker substitutes its constants into
    its return expressions rather than repeating a formula that can drift from it.
    """
    source = (root / "src" / "display" / "band.zig").read_text(encoding="utf-8")
    consts = dict(re.findall(r"pub const (LOG_ROWS|LOG_ROW): \w+ = (\d+);", source))
    if set(consts) != {"LOG_ROWS", "LOG_ROW"}:
        raise ValueError("LOG_ROWS and LOG_ROW are not both declared")
    rows = {}
    for name in ("top", "bottom"):
        m = re.search(rf"pub fn {name}\(screen_h: i32\) i32 \{{\s*return ([^;]+);", source)
        if m is None:
            raise ValueError(f"no single-line return for {name}")
        expr = re.sub(r"@as\(\s*\w+\s*,\s*([^)]+)\)", r"(\1)", m.group(1))
        expr = expr.replace("screen_h", "720")
        for const, value in consts.items():
            expr = re.sub(rf"\b{const}\b", value, expr)
        if not re.fullmatch(r"[\d\s()+\-*/]+", expr):
            raise ValueError(f"unexpected arithmetic in {name}: {expr.strip()}")
        rows[name] = int(eval(expr, {"__builtins__": {}}, {}))  # digits, spaces and operators only
    return rows["top"], rows["bottom"]


def check_band_numbers(texts, root=ROOT):
    """Errors for every band row a document quotes that the engine does not compute (P43-07)."""
    try:
        top, bottom = band_rows(root)
    except (OSError, ValueError) as exc:
        return [f"src/display/band.zig: cannot read the band's rows: {exc}"]
    found = []
    for path, text in texts.items():
        if path.parent.name == "archive":
            continue
        for line_no, line in enumerate(text.splitlines(), 1):
            if "band" not in line.lower():
                continue
            for which, phrases, want in (("top", BAND_TOP_PHRASES, top), ("bottom", BAND_BOTTOM_PHRASES, bottom)):
                for pattern in phrases:
                    for m in re.finditer(pattern, line):
                        if int(m.group(1)) != want:
                            found.append(f"{path.relative_to(root)}:{line_no}: the band's {which} is {want} "
                                         f"pixels at 1280x720, not {m.group(1)}")
            for m in ROLLING_BAND_PAIR.finditer(line):
                if (int(m.group(1)), int(m.group(2))) != (top, bottom):
                    found.append(f"{path.relative_to(root)}:{line_no}: the band's rows are {top} to {bottom}, "
                                 f"not {m.group(1)} to {m.group(2)}")
    return found


def read(path):
    text = path.read_text(encoding="utf-8")
    return re.sub(r"<!--.*?-->", "", text, flags=re.S)


def where(path, text, pos):
    return f"{path.relative_to(ROOT)}:{text.count(chr(10), 0, pos) + 1}"


def section(text, heading):
    m = re.search(rf"^## {heading}\b.*?(?=^## |\Z)", text, flags=re.M | re.S)
    return (m.group(0), m.start()) if m else ("", 0)


def main():
    template = "--template" in sys.argv[1:]
    docs = [ROOT / d for d in DOCS if (ROOT / d).is_file()]
    for folder in ("docs/archive",):
        if (ROOT / folder).is_dir():
            docs += sorted(p for p in (ROOT / folder).iterdir()
                           if p.suffix in (".md", ".html") and not p.name.startswith("_"))
    texts = {p: read(p) for p in docs}

    if not template:
        for path, text in texts.items():
            for m in re.finditer(r"\{\{[^}]*\}\}", text):
                errors.append(f"{where(path, text, m.start())}: placeholder left: {m.group(0)[:60]}")

    roadmap = next((p for p in (ROOT / "ROADMAP.md", ROOT / "docs" / "ROADMAP.md") if p in texts), None)
    items = set()
    if roadmap is None:
        errors.append("no ROADMAP.md (looked in the root and in docs/)")
    else:
        text, phase = texts[roadmap], None
        for m in re.finditer(r"^## Phase (\d+)|^- \[(.)\] (P(\d+)-(\d+))\b", text, flags=re.M):
            if m.group(1):
                phase = m.group(1)
                continue
            box, item, item_phase = m.group(2), m.group(3), m.group(4)
            if item in items:
                errors.append(f"{where(roadmap, text, m.start())}: {item} is used twice")
            items.add(item)
            if box not in " x~-":
                errors.append(f"{where(roadmap, text, m.start())}: {item} has checkbox [{box}]; use [ ], [~], [x] or [-]")
            if phase is not None and item_phase != phase:
                errors.append(f"{where(roadmap, text, m.start())}: {item} is filed under Phase {phase}")
        # Archived phases keep their IDs reserved.
        for path, text in texts.items():
            if path.parent.name == "archive":
                items.update(m.group(1) for m in re.finditer(r"^- \[.\] (P\d+-\d+)\b", text, flags=re.M))

    decisions_path = ROOT / "docs" / "DECISIONS.md"
    decisions, supersessions, questions, tensions = set(), [], set(), set()
    if decisions_path in texts:
        text, last = texts[decisions_path], 0
        for m in re.finditer(r"^## D-(\d{3})\b([^\n]*)", text, flags=re.M):
            number = int(m.group(1))
            if f"D-{m.group(1)}" in decisions:
                errors.append(f"{where(decisions_path, text, m.start())}: D-{m.group(1)} is used twice")
            elif number < last:
                errors.append(f"{where(decisions_path, text, m.start())}: D-{m.group(1)} comes after D-{last:03d}")
            decisions.add(f"D-{m.group(1)}")
            last = max(last, number)
            by = re.search(r"superseded by D-(\d{3})", m.group(2))
            if by:
                supersessions.append((number, int(by.group(1)), m.start()))
        for number, by, pos in supersessions:
            if f"D-{by:03d}" in decisions and by <= number:
                errors.append(f"{where(decisions_path, text, pos)}: D-{number:03d} is superseded by an earlier "
                              f"decision, D-{by:03d}")
        for m in re.finditer(r"^(?:### Q-(\d{3})\b|- \*\*Q-(\d{3})\*\*)", text, flags=re.M):
            q_num = m.group(1) or m.group(2)
            q_id = f"Q-{q_num}"
            if q_id in questions:
                errors.append(f"{where(decisions_path, text, m.start())}: {q_id} is used twice")
            questions.add(q_id)
        last_t = 0
        for m in re.finditer(r"^### T-(\d{3})\b", text, flags=re.M):
            number = int(m.group(1))
            t_id = f"T-{m.group(1)}"
            if t_id in tensions:
                errors.append(f"{where(decisions_path, text, m.start())}: {t_id} is used twice")
            elif number < last_t:
                errors.append(f"{where(decisions_path, text, m.start())}: {t_id} comes after T-{last_t:03d}")
            tensions.add(t_id)
            last_t = max(last_t, number)

    errors.extend(check_band_numbers(texts))

    for path, text in texts.items():
        for m in INVISIBLE_RE.finditer(text):
            errors.append(f"{where(path, text, m.start())}: invisible or bidirectional control character "
                          f"U+{ord(m.group(0)):04X}")
        if roadmap is not None:
            for m in ITEM_RE.finditer(text):
                if m.group(0) not in items:
                    errors.append(f"{where(path, text, m.start())}: {m.group(0)} is not in the roadmap")
        if decisions_path in texts:
            for m in DECISION_RE.finditer(text):
                if m.group(0) not in decisions:
                    errors.append(f"{where(path, text, m.start())}: {m.group(0)} is not in DECISIONS.md")
            for m in QUESTION_RE.finditer(text):
                if m.group(0) not in questions:
                    errors.append(f"{where(path, text, m.start())}: {m.group(0)} is not in DECISIONS.md's open questions")
            for m in TENSION_RE.finditer(text):
                if m.group(0) not in tensions:
                    errors.append(f"{where(path, text, m.start())}: {m.group(0)} is not in DECISIONS.md's held tensions")
        for m in LINK_RE.finditer(text):
            target = (m.group(1) or m.group(2)).split("#")[0]
            if not target or "{{" in target or re.match(r"[a-z][a-z0-9+.-]*:", target):
                continue
            if not (path.parent / target).exists():
                errors.append(f"{where(path, text, m.start())}: link to {target}, which does not exist")

    agents = ROOT / "AGENTS.md"
    if agents in texts:
        layout, offset = section(texts[agents], "Layout")
        for m in re.finditer(r"^\| `([^`]+)` \|", layout, flags=re.M):
            if "{{" not in m.group(1) and not (ROOT / m.group(1)).exists():
                errors.append(f"{where(agents, texts[agents], offset + m.start())}: Layout lists {m.group(1)}, "
                              f"which does not exist")

    handoff = ROOT / "docs" / "HANDOFF.md"
    if handoff in texts:
        text = texts[handoff]
        session_re = re.compile(r"^### Session (\d+)\b([^\n]*)", flags=re.M)
        sessions = [(m.group(1), (DATE_RE.search(m.group(2)) or [None])[0]) for m in session_re.finditer(text)]
        seen = set()
        for path in [handoff] + [p for p in texts if p.parent.name == "archive"]:
            for m in session_re.finditer(texts[path]):
                if m.group(1) in seen:
                    errors.append(f"{where(path, texts[path], m.start())}: a second entry for Session {m.group(1)}")
                seen.add(m.group(1))
        updated = re.search(r"Last updated:\s*(\d{4}-\d{2}-\d{2})", text)
        newest = max((d for _, d in sessions if d), default=None)
        if not updated:
            if not template:
                warnings.append("docs/HANDOFF.md: no 'Last updated: YYYY-MM-DD' line in Current state")
        elif newest and updated.group(1) < newest:
            warnings.append(f"docs/HANDOFF.md: Current state was last updated {updated.group(1)}, "
                            f"but the session log has an entry from {newest}")
        if len(sessions) > LOG_LIMIT:
            warnings.append(f"docs/HANDOFF.md: {len(sessions)} session-log entries; move all but the newest "
                            f"{LOG_LIMIT} to docs/archive/")
        current, _ = section(text, "Current state")
        if current.count("\n") > CURRENT_STATE_LINES:
            warnings.append(f"docs/HANDOFF.md: Current state is {current.count(chr(10))} lines (limit "
                            f"{CURRENT_STATE_LINES}); move history to the session log")

    # 3x Documentation Scheme validation (scheme/bespoke.manual.json)
    manual_path = ROOT / "scheme" / "bespoke.manual.json"
    if manual_path.is_file():
        try:
            import json
            import importlib.util
            spec = importlib.util.spec_from_file_location("manual", ROOT / "tools" / "manual.py")
            manual = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(manual)
            data = json.loads(manual_path.read_text(encoding="utf-8"))
            m_errors, m_warnings = manual.validate(data, check_evidence=True, root=ROOT)
            for err in m_errors:
                errors.append(f"scheme/bespoke.manual.json: {err}")
            for warn in m_warnings:
                warnings.append(f"scheme/bespoke.manual.json: {warn}")
        except Exception as e:
            errors.append(f"scheme/bespoke.manual.json: failed to validate manual: {e}")

    # Engine / proof separation lint (tools/check_separation.py, P32-06, D-031): proof names in
    # non-test src/ code may not exceed the committed baseline; a stale (too high) baseline warns.
    sep_tool = ROOT / "tools" / "check_separation.py"
    if sep_tool.is_file():
        try:
            import importlib.util
            spec = importlib.util.spec_from_file_location("check_separation", sep_tool)
            sep = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(sep)
            s_errors, s_notes = sep.check(ROOT)
            errors.extend(f"separation: {e}" for e in s_errors)
            warnings.extend(f"separation: {n}" for n in s_notes)
        except Exception as e:
            errors.append(f"tools/check_separation.py: failed to run: {e}")

    # Third-party name lint (tools/check_third_party.py, P35-01, Q-005): borrowed titles,
    # characters, places, and lines may not exceed the committed baseline.
    tp_tool = ROOT / "tools" / "check_third_party.py"
    if tp_tool.is_file():
        try:
            import importlib.util
            spec = importlib.util.spec_from_file_location("check_third_party", tp_tool)
            tp = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(tp)
            t_errors, t_notes = tp.check(ROOT)
            errors.extend(f"third-party: {e}" for e in t_errors)
            warnings.extend(f"third-party: {n}" for n in t_notes)
        except Exception as e:
            errors.append(f"tools/check_third_party.py: failed to run: {e}")

    for line in errors:
        print(f"ERROR {line}")
    for line in warnings:
        print(f"WARN  {line}")
    print(f"{len(errors)} error(s), {len(warnings)} warning(s) in {len(texts)} file(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
