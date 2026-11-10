#!/usr/bin/env python3
"""Build, lint, and review portable What/How/Why manuals from a small JSON content model."""

from __future__ import annotations

import argparse
import copy
import html
import json
import re
import sys
import time
import urllib.error
import urllib.request
from datetime import date
from pathlib import Path
from typing import Any, Iterable, Optional


ID_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
PLACEHOLDER_RE = re.compile(r"\{\{\s*([a-zA-Z0-9_.-]+)\s*\}\}")
TODO_RE = re.compile(r"\b(?:todo|tbd|fixme|lorem ipsum)\b", re.IGNORECASE)
HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")
COMMIT_RE = re.compile(r"^[0-9a-fA-F]{7,40}$")
EM_DASH_RE = re.compile("\u2014")
INVISIBLE_RE = re.compile(r"[\u180e\u200b-\u200f\u202a-\u202e\u2060-\u206f\ufeff]")
VALIDATING_OPENER_RE = re.compile(
    r"(?im)(?:^|[.!?]\s+)(that makes sense|i understand|great question|you'?re absolutely right)\b"
)
SEESAW_RE = re.compile(
    r"(?i)\b(?:it'?s|it is|this is)\s+not\s+[^.\n]{1,60},?\s+(?:it'?s|it is|this is)\b"
)
BLENDED_RE = re.compile(r"(?i)\b(?:bittersweet|mixed feelings|it is what it is)\b")

BASIS_VALUES = ("recorded", "observed", "inferred", "external")
EVIDENCE_KINDS = ("source", "test", "decision", "spec", "url", "command", "document")
REVIEW_INTERVAL_DAYS = 180

ALLOWED_ROOT = {"$schema", "project", "manual", "theme", "sections"}
ALLOWED_PROJECT = {"name", "short_name", "version", "repository"}
ALLOWED_MANUAL = {"title", "subtitle", "description", "badges", "footer", "reviewed"}
ALLOWED_SECTION = {"id", "title", "description", "entries"}
ALLOWED_ENTRY = {
    "id",
    "title",
    "summary",
    "synopsis",
    "tags",
    "what",
    "how",
    "why",
    "why_basis",
    "evidence",
    "related",
}
ALLOWED_THEME = {"accent", "accent_secondary", "icon"}
ALLOWED_EVIDENCE = {"label", "target", "kind"}
ALLOWED_REVIEWED = {"date", "commit", "by", "interval_days"}

LINT_RULES = {
    "L001": "em dash",
    "L002": "invisible or bidirectional character",
    "L003": "validating opener",
    "L004": "seesaw definition",
    "L005": "blended emotional plateau",
}


class ManualError(Exception):
    pass


def load_source(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ManualError(f"source not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ManualError(f"invalid JSON at {path}:{exc.lineno}:{exc.colno}: {exc.msg}") from exc
    if not isinstance(data, dict):
        raise ManualError("the manual root must be a JSON object")
    return data


def scalar(value: str) -> Any:
    try:
        parsed = json.loads(value)
    except json.JSONDecodeError:
        return value
    return parsed if not isinstance(parsed, (dict, list)) else value


def apply_override(data: dict[str, Any], expression: str) -> None:
    if "=" not in expression:
        raise ManualError(f"override must be PATH=VALUE: {expression!r}")
    dotted, raw = expression.split("=", 1)
    keys = [part for part in dotted.split(".") if part]
    if not keys:
        raise ManualError(f"override has no path: {expression!r}")
    node: Any = data
    for key in keys[:-1]:
        if not isinstance(node, dict) or key not in node:
            raise ManualError(f"override path does not exist: {dotted}")
        node = node[key]
    if not isinstance(node, dict) or keys[-1] not in node:
        raise ManualError(f"override path does not exist: {dotted}")
    node[keys[-1]] = scalar(raw)


def lookup(data: dict[str, Any], dotted: str) -> Any:
    node: Any = data
    for key in dotted.split("."):
        if not isinstance(node, dict) or key not in node:
            raise ManualError(f"unknown placeholder: {{{{{dotted}}}}}")
        node = node[key]
    if isinstance(node, (dict, list)):
        raise ManualError(f"placeholder must resolve to a scalar: {{{{{dotted}}}}}")
    return node


def expand_placeholders(value: Any, root: dict[str, Any]) -> Any:
    if isinstance(value, str):
        return PLACEHOLDER_RE.sub(lambda match: str(lookup(root, match.group(1))), value)
    if isinstance(value, list):
        return [expand_placeholders(item, root) for item in value]
    if isinstance(value, dict):
        return {key: expand_placeholders(item, root) for key, item in value.items()}
    return value


def dimension_text(value: Any) -> str:
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, list):
        return " ".join(str(item).strip() for item in value)
    if isinstance(value, dict):
        lead = str(value.get("lead", "")).strip()
        points = " ".join(str(item).strip() for item in value.get("points", []))
        return f"{lead} {points}".strip()
    return ""


def check_evidence_target(
    target: str,
    *,
    kind: Optional[str],
    location: str,
    root: Path,
    warnings: list[str],
) -> None:
    if kind in ("command", "url"):
        return
    if re.match(r"^(?:https?://|mailto:|#)", target, re.IGNORECASE):
        return
    if any(char.isspace() for char in target):
        return
    path_text = target.split("#", 1)[0]
    if not path_text:
        return
    candidate_path = Path(path_text)
    if candidate_path.is_absolute():
        warnings.append(f"{location}: evidence target must be relative to the evidence root")
        return
    try:
        resolved_root = root.resolve()
        candidate = (resolved_root / candidate_path).resolve()
        candidate.relative_to(resolved_root)
    except (OSError, ValueError):
        warnings.append(f"{location}: evidence target resolves outside the evidence root")
        return
    if not candidate.exists():
        warnings.append(f"{location}: evidence target not found: {path_text}")


def check_url_target(
    target: str,
    *,
    location: str,
    warnings: list[str],
    timeout: float,
) -> None:
    if not re.match(r"^https?://", target, re.IGNORECASE):
        return
    headers = {"User-Agent": "3x-documentation-check/1.0"}
    try:
        request = urllib.request.Request(target, method="HEAD", headers=headers)
        with urllib.request.urlopen(request, timeout=timeout) as response:
            status = getattr(response, "status", 200)
            if status >= 400:
                warnings.append(f"{location}: URL returned HTTP {status}: {target}")
    except urllib.error.HTTPError as exc:
        if exc.code in (405, 501):
            try:
                request = urllib.request.Request(
                    target,
                    method="GET",
                    headers={**headers, "Range": "bytes=0-0"},
                )
                with urllib.request.urlopen(request, timeout=timeout) as response:
                    status = getattr(response, "status", 200)
                    if status >= 400:
                        warnings.append(f"{location}: URL returned HTTP {status}: {target}")
                return
            except (urllib.error.URLError, TimeoutError, OSError, ValueError) as retry_exc:
                warnings.append(f"{location}: URL check failed: {target} ({retry_exc})")
                return
        warnings.append(f"{location}: URL returned HTTP {exc.code}: {target}")
    except (urllib.error.URLError, TimeoutError, OSError, ValueError) as exc:
        warnings.append(f"{location}: URL check failed: {target} ({exc})")


def validate(
    data: dict[str, Any],
    *,
    check_evidence: bool = False,
    root: Optional[Path] = None,
    check_urls: bool = False,
    url_timeout: float = 5.0,
    today: Optional[date] = None,
) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    current_day = today or date.today()
    evidence_root = (root or Path.cwd()).resolve()

    unknown_root = set(data) - ALLOWED_ROOT
    if unknown_root:
        errors.append(f"root: unknown field(s): {', '.join(sorted(unknown_root))}")

    project = data.get("project")
    if not isinstance(project, dict):
        errors.append("project: required object")
    else:
        for field in ("name", "version"):
            if field not in project:
                errors.append(f"project.{field}: required value")
        name = project.get("name")
        if not isinstance(name, str) or not name.strip():
            errors.append("project.name: required string")
        version = project.get("version")
        if (
            isinstance(version, bool)
            or not isinstance(version, (str, int, float))
            or not str(version).strip()
        ):
            errors.append("project.version: required string or number")
        for field in ("short_name", "repository"):
            value = project.get(field)
            if value is not None and not isinstance(value, str):
                errors.append(f"project.{field}: must be a string")
        for key, value in project.items():
            if key in ALLOWED_PROJECT:
                continue
            if value is None or isinstance(value, (dict, list)):
                errors.append(f"project.{key}: additional values must be scalars")

    manual = data.get("manual")
    if not isinstance(manual, dict):
        errors.append("manual: required object")
    else:
        unknown_manual = set(manual) - ALLOWED_MANUAL
        if unknown_manual:
            errors.append(f"manual: unknown field(s): {', '.join(sorted(unknown_manual))}")
        title = manual.get("title")
        if not isinstance(title, str) or not title.strip():
            errors.append("manual.title: required string")
        for field in ("subtitle", "description", "footer"):
            value = manual.get(field)
            if value is not None and not isinstance(value, str):
                errors.append(f"manual.{field}: must be a string")
        badges = manual.get("badges")
        if badges is not None:
            if not isinstance(badges, list):
                errors.append("manual.badges: must be an array")
            elif not all(isinstance(badge, str) for badge in badges):
                errors.append("manual.badges: every badge must be a string")
        reviewed = manual.get("reviewed")
        if reviewed is None:
            warnings.append("manual.reviewed: missing review date and commit")
        elif not isinstance(reviewed, dict):
            errors.append("manual.reviewed: must be an object")
        else:
            unknown_reviewed = set(reviewed) - ALLOWED_REVIEWED
            if unknown_reviewed:
                errors.append(
                    f"manual.reviewed: unknown field(s): {', '.join(sorted(unknown_reviewed))}"
                )
            date_text = reviewed.get("date")
            commit = reviewed.get("commit")
            by = reviewed.get("by")
            interval = reviewed.get("interval_days", REVIEW_INTERVAL_DAYS)
            parsed_date: Optional[date] = None
            if not isinstance(date_text, str) or not date_text.strip():
                errors.append("manual.reviewed.date: required YYYY-MM-DD string")
            else:
                try:
                    parsed_date = date.fromisoformat(date_text)
                except ValueError:
                    errors.append("manual.reviewed.date: expected YYYY-MM-DD")
            if not isinstance(commit, str) or not COMMIT_RE.match(commit):
                errors.append("manual.reviewed.commit: expected 7 to 40 hexadecimal characters")
            if by is not None and (not isinstance(by, str) or not by.strip()):
                errors.append("manual.reviewed.by: must be a non-empty string")
            if isinstance(interval, bool) or not isinstance(interval, int) or interval < 1:
                errors.append("manual.reviewed.interval_days: must be a positive integer")
            elif parsed_date is not None:
                age = (current_day - parsed_date).days
                if age > interval:
                    warnings.append(
                        f"manual.reviewed: last review was {age} days ago; "
                        f"interval is {interval} days"
                    )

    theme = data.get("theme", {})
    if not isinstance(theme, dict):
        errors.append("theme: must be an object")
    else:
        unknown_theme = set(theme) - ALLOWED_THEME
        if unknown_theme:
            errors.append(f"theme: unknown field(s): {', '.join(sorted(unknown_theme))}")
        for field in ("accent", "accent_secondary"):
            value = theme.get(field)
            if value is not None and (not isinstance(value, str) or not HEX_RE.match(value)):
                errors.append(f"theme.{field}: expected a six-digit hex color")
        icon = theme.get("icon")
        if icon is not None and not isinstance(icon, str):
            errors.append("theme.icon: must be a string")

    sections = data.get("sections")
    if not isinstance(sections, list) or not sections:
        errors.append("sections: at least one section is required")
        return errors, warnings

    seen: set[str] = set()
    references: list[tuple[str, str]] = []
    for section_index, section in enumerate(sections):
        location = f"sections[{section_index}]"
        if not isinstance(section, dict):
            errors.append(f"{location}: must be an object")
            continue
        unknown_section = set(section) - ALLOWED_SECTION
        if unknown_section:
            errors.append(f"{location}: unknown field(s): {', '.join(sorted(unknown_section))}")
        section_id = section.get("id")
        if not isinstance(section_id, str) or not ID_RE.match(section_id):
            errors.append(f"{location}.id: use lowercase kebab-case")
        elif section_id in seen:
            errors.append(f"{location}.id: duplicate ID {section_id!r}")
        else:
            seen.add(section_id)
        if not isinstance(section.get("title"), str) or not section["title"].strip():
            errors.append(f"{location}.title: required string")
        description = section.get("description")
        if description is not None and not isinstance(description, str):
            errors.append(f"{location}.description: must be a string")
        entries = section.get("entries")
        if not isinstance(entries, list) or not entries:
            errors.append(f"{location}.entries: at least one entry is required")
            continue
        for entry_index, entry in enumerate(entries):
            entry_location = f"{location}.entries[{entry_index}]"
            if not isinstance(entry, dict):
                errors.append(f"{entry_location}: must be an object")
                continue
            unknown_entry = set(entry) - ALLOWED_ENTRY
            if unknown_entry:
                errors.append(
                    f"{entry_location}: unknown field(s): {', '.join(sorted(unknown_entry))}"
                )
            entry_id = entry.get("id")
            if not isinstance(entry_id, str) or not ID_RE.match(entry_id):
                errors.append(f"{entry_location}.id: use lowercase kebab-case")
            elif entry_id in seen:
                errors.append(f"{entry_location}.id: duplicate ID {entry_id!r}")
            else:
                seen.add(entry_id)
            if not isinstance(entry.get("title"), str) or not entry["title"].strip():
                errors.append(f"{entry_location}.title: required string")
            basis = entry.get("why_basis")
            if basis is None:
                errors.append(f"{entry_location}.why_basis: required field")
            elif not isinstance(basis, str) or basis not in BASIS_VALUES:
                errors.append(
                    f"{entry_location}.why_basis: expected one of {', '.join(BASIS_VALUES)}"
                )
            else:
                why_text = dimension_text(entry.get("why"))
                if basis == "recorded" and re.search(r"\binferred\b", why_text, re.IGNORECASE):
                    warnings.append(
                        f"{entry_location}.why_basis: recorded basis conflicts with inferred wording"
                    )
            for dimension in ("what", "how", "why"):
                value = entry.get(dimension)
                valid_dimension = (
                    isinstance(value, str)
                    or (
                        isinstance(value, list)
                        and bool(value)
                        and all(isinstance(item, str) and item.strip() for item in value)
                    )
                    or (
                        isinstance(value, dict)
                        and not (set(value) - {"lead", "points"})
                        and isinstance(value.get("lead", ""), str)
                        and (
                            bool(str(value.get("lead", "")).strip())
                            or bool(value.get("points"))
                        )
                        and isinstance(value.get("points", []), list)
                        and all(
                            isinstance(item, str) and item.strip()
                            for item in value.get("points", [])
                        )
                    )
                )
                text = dimension_text(value)
                if not valid_dimension:
                    errors.append(
                        f"{entry_location}.{dimension}: expected a string, string array, "
                        "or lead/points object"
                    )
                if not text:
                    errors.append(f"{entry_location}.{dimension}: required content")
                elif TODO_RE.search(text):
                    errors.append(f"{entry_location}.{dimension}: contains placeholder text")
            summary = entry.get("summary")
            if summary is not None and not isinstance(summary, str):
                errors.append(f"{entry_location}.summary: must be a string")
            synopsis = entry.get("synopsis")
            if synopsis is not None and not isinstance(synopsis, str):
                errors.append(f"{entry_location}.synopsis: must be a string")
            tags = entry.get("tags", [])
            if not isinstance(tags, list) or not all(isinstance(item, str) for item in tags):
                errors.append(f"{entry_location}.tags: must be an array of strings")
            evidence = entry.get("evidence", [])
            if not isinstance(evidence, list):
                errors.append(f"{entry_location}.evidence: must be an array")
            elif not evidence:
                warnings.append(f"{entry_location}: has no evidence")
            else:
                for evidence_index, item in enumerate(evidence):
                    item_location = f"{entry_location}.evidence[{evidence_index}]"
                    if isinstance(item, str):
                        if not item.strip():
                            errors.append(f"{item_location}: expected a non-empty target")
                            continue
                        target = item
                        kind: Optional[str] = None
                        target_location = item_location
                    elif isinstance(item, dict):
                        unknown_evidence = set(item) - ALLOWED_EVIDENCE
                        if unknown_evidence:
                            errors.append(
                                f"{item_location}: unknown field(s): "
                                f"{', '.join(sorted(unknown_evidence))}"
                            )
                        label = item.get("label")
                        target = item.get("target")
                        kind_value = item.get("kind")
                        if not isinstance(label, str) or not label.strip():
                            errors.append(f"{item_location}.label: required string")
                        if not isinstance(target, str) or not target.strip():
                            errors.append(f"{item_location}.target: required string")
                            continue
                        if kind_value is not None and (
                            not isinstance(kind_value, str) or kind_value not in EVIDENCE_KINDS
                        ):
                            errors.append(
                                f"{item_location}.kind: expected one of "
                                f"{', '.join(EVIDENCE_KINDS)}"
                            )
                        kind = kind_value if isinstance(kind_value, str) else None
                        target_location = f"{item_location}.target"
                    else:
                        errors.append(
                            f"{item_location}: expected a string or label/target object"
                        )
                        continue
                    if check_evidence:
                        check_evidence_target(
                            target,
                            kind=kind,
                            location=target_location,
                            root=evidence_root,
                            warnings=warnings,
                        )
                    if check_urls:
                        check_url_target(
                            target,
                            location=target_location,
                            warnings=warnings,
                            timeout=url_timeout,
                        )
            related_items = entry.get("related", [])
            if not isinstance(related_items, list) or not all(
                isinstance(item, str) for item in related_items
            ):
                errors.append(f"{entry_location}.related: must be an array of IDs")
                related_items = []
            for related in related_items:
                references.append((entry_location, related))

    for location, target in references:
        if target not in seen:
            warnings.append(f"{location}.related: unknown ID {target!r}")
    return errors, warnings


def review(
    data: dict[str, Any],
    *,
    check_evidence: bool = False,
    root: Optional[Path] = None,
    check_urls: bool = False,
    url_timeout: float = 5.0,
    today: Optional[date] = None,
) -> tuple[list[str], list[str], list[dict[str, str]]]:
    errors, warnings = validate(
        data,
        check_evidence=check_evidence,
        root=root,
        check_urls=check_urls,
        url_timeout=url_timeout,
        today=today,
    )
    items: list[dict[str, str]] = []
    current_day = today or date.today()
    manual = data.get("manual")
    if isinstance(manual, dict):
        reviewed = manual.get("reviewed")
        if not isinstance(reviewed, dict):
            items.append(
                {
                    "location": "manual.reviewed",
                    "kind": "unreviewed",
                    "message": "no review date and commit",
                }
            )
        else:
            date_text = reviewed.get("date")
            interval = reviewed.get("interval_days", REVIEW_INTERVAL_DAYS)
            try:
                parsed_date = date.fromisoformat(date_text)
                age = (current_day - parsed_date).days
                if (
                    isinstance(interval, int)
                    and not isinstance(interval, bool)
                    and age > interval
                ):
                    items.append(
                        {
                            "location": "manual.reviewed",
                            "kind": "stale-review",
                            "message": f"last review was {age} days ago; "
                            f"interval is {interval} days",
                        }
                    )
            except (TypeError, ValueError):
                pass
    sections = data.get("sections")
    if isinstance(sections, list):
        for section_index, section in enumerate(sections):
            if not isinstance(section, dict):
                continue
            entries = section.get("entries")
            if not isinstance(entries, list):
                continue
            for entry_index, entry in enumerate(entries):
                if not isinstance(entry, dict):
                    continue
                location = f"sections[{section_index}].entries[{entry_index}]"
                basis = entry.get("why_basis")
                if basis == "inferred":
                    items.append(
                        {
                            "location": location,
                            "kind": "inferred-rationale",
                            "message": "why_basis is inferred",
                        }
                    )
                evidence = entry.get("evidence")
                if not isinstance(evidence, list) or not evidence:
                    items.append(
                        {
                            "location": location,
                            "kind": "missing-evidence",
                            "message": "entry has no evidence",
                        }
                    )
                    continue
                kinds = {
                    item.get("kind")
                    for item in evidence
                    if isinstance(item, dict) and isinstance(item.get("kind"), str)
                }
                required = {
                    "recorded": {"decision", "spec"},
                    "observed": {"source", "test", "document", "spec"},
                    "external": {"url", "spec"},
                }
                if basis in required and kinds and not (kinds & required[basis]):
                    items.append(
                        {
                            "location": location,
                            "kind": "weak-evidence",
                            "message": f"{basis} rationale lacks "
                            f"{'/'.join(sorted(required[basis]))} evidence",
                        }
                    )
    return errors, warnings, items


def dimension_fields(value: Any, location: str) -> Iterable[tuple[str, str]]:
    if isinstance(value, str) and value.strip():
        yield location, value
    elif isinstance(value, list):
        for index, item in enumerate(value):
            if isinstance(item, str) and item.strip():
                yield f"{location}[{index}]", item
    elif isinstance(value, dict):
        lead = value.get("lead")
        if isinstance(lead, str) and lead.strip():
            yield f"{location}.lead", lead
        points = value.get("points")
        if isinstance(points, list):
            for index, item in enumerate(points):
                if isinstance(item, str) and item.strip():
                    yield f"{location}.points[{index}]", item


def prose_fields(data: dict[str, Any]) -> Iterable[tuple[str, str]]:
    manual = data.get("manual")
    if isinstance(manual, dict):
        for field in ("title", "subtitle", "description", "footer"):
            value = manual.get(field)
            if isinstance(value, str) and value.strip():
                yield f"manual.{field}", value
        badges = manual.get("badges")
        if isinstance(badges, list):
            for index, badge in enumerate(badges):
                if isinstance(badge, str) and badge.strip():
                    yield f"manual.badges[{index}]", badge
    sections = data.get("sections")
    if not isinstance(sections, list):
        return
    for section_index, section in enumerate(sections):
        if not isinstance(section, dict):
            continue
        for field in ("title", "description"):
            value = section.get(field)
            if isinstance(value, str) and value.strip():
                yield f"sections[{section_index}].{field}", value
        entries = section.get("entries")
        if not isinstance(entries, list):
            continue
        for entry_index, entry in enumerate(entries):
            if not isinstance(entry, dict):
                continue
            prefix = f"sections[{section_index}].entries[{entry_index}]"
            for field in ("title", "summary"):
                value = entry.get(field)
                if isinstance(value, str) and value.strip():
                    yield f"{prefix}.{field}", value
            for dimension in ("what", "how", "why"):
                yield from dimension_fields(entry.get(dimension), f"{prefix}.{dimension}")
            evidence = entry.get("evidence")
            if isinstance(evidence, list):
                for evidence_index, item in enumerate(evidence):
                    if isinstance(item, dict):
                        label = item.get("label")
                        if isinstance(label, str) and label.strip():
                            yield f"{prefix}.evidence[{evidence_index}].label", label


def clip(value: str, limit: int = 90) -> str:
    value = " ".join(value.split())
    return value if len(value) <= limit else value[: limit - 3] + "..."


def lint_text(text: str) -> list[tuple[str, str, str]]:
    findings: list[tuple[str, str, str]] = []
    for match in EM_DASH_RE.finditer(text):
        findings.append(
            ("L001", "", clip(text[max(0, match.start() - 30): match.end() + 30]))
        )
    for match in INVISIBLE_RE.finditer(text):
        findings.append(
            (
                "L002",
                f"U+{ord(match.group(0)):04X}",
                clip(text[max(0, match.start() - 30): match.end() + 30]),
            )
        )
    for match in VALIDATING_OPENER_RE.finditer(text):
        findings.append(("L003", "", clip(match.group(1))))
    for match in SEESAW_RE.finditer(text):
        findings.append(("L004", "", clip(match.group(0))))
    for match in BLENDED_RE.finditer(text):
        findings.append(("L005", "", clip(match.group(0))))
    return findings


def lint(data: dict[str, Any]) -> list[str]:
    findings: list[str] = []
    for location, text in prose_fields(data):
        for rule_id, detail, snippet in lint_text(text):
            label = LINT_RULES[rule_id] + (f" {detail}" if detail else "")
            findings.append(f"{location}: {label}: {snippet}")
    return findings


def lint_findings(data: dict[str, Any]) -> list[dict[str, str]]:
    findings: list[dict[str, str]] = []
    for location, text in prose_fields(data):
        for rule_id, detail, snippet in lint_text(text):
            findings.append(
                {
                    "rule": rule_id,
                    "name": LINT_RULES[rule_id],
                    "detail": detail,
                    "location": location,
                    "snippet": snippet,
                }
            )
    return findings


def inline(text: Any) -> str:
    """Render a deliberately small, HTML-escaped inline notation."""
    value = html.escape(str(text), quote=True)
    tokens: list[str] = []

    def stash(fragment: str) -> str:
        tokens.append(fragment)
        return f"\x00{len(tokens) - 1}\x00"

    value = re.sub(r"`([^`]+)`", lambda m: stash(f"<code>{m.group(1)}</code>"), value)

    def link(match: re.Match[str]) -> str:
        label, target = match.group(1), html.unescape(match.group(2))
        safe_link = re.match(
            r"^(?:https?://|mailto:|#[a-z0-9_-]+$|(?:\.\.?/)?[a-z0-9][a-z0-9._/-]*(?:#[a-z0-9_-]+)?$)",
            target,
            re.IGNORECASE,
        )
        if not safe_link:
            return match.group(0)
        safe_target = html.escape(target, quote=True)
        return stash(f'<a href="{safe_target}" rel="noreferrer">{label}</a>')

    value = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link, value)
    value = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", value)
    value = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<em>\1</em>", value)
    for index, token in enumerate(tokens):
        value = value.replace(f"\x00{index}\x00", token)
    return value


def basis_badge(basis: Any) -> str:
    if basis not in BASIS_VALUES:
        return ""
    return (
        f'<span class="basis basis-{basis}" '
        f'title="Provenance of this rationale">{basis}</span>'
    )


def review_metadata(manual: dict[str, Any], project: dict[str, Any]) -> str:
    reviewed = manual.get("reviewed")
    if not isinstance(reviewed, dict):
        return ""
    date_text = str(reviewed.get("date", ""))
    commit = str(reviewed.get("commit", ""))
    if not date_text or not commit:
        return ""
    repository = str(project.get("repository", "")).rstrip("/")
    if repository.startswith("https://github.com/"):
        commit_html = (
            f'<a href="{html.escape(repository + "/commit/" + commit, quote=True)}" '
            f'rel="noreferrer"><code>{html.escape(commit)}</code></a>'
        )
    else:
        commit_html = f"<code>{html.escape(commit)}</code>"
    return (
        f'<p class="reviewed">Last reviewed '
        f'<time datetime="{html.escape(date_text, quote=True)}">'
        f"{html.escape(date_text)}</time> · {commit_html}</p>"
    )


def render_dimension(label: str, kind: str, value: Any, badge: str = "") -> str:
    if isinstance(value, str):
        body = f"<p>{inline(value)}</p>"
    elif isinstance(value, list):
        items = "".join(f"<li>{inline(item)}</li>" for item in value)
        body = f"<ol>{items}</ol>"
    else:
        lead = value.get("lead", "") if isinstance(value, dict) else ""
        points = value.get("points", []) if isinstance(value, dict) else []
        lead_html = f"<p>{inline(lead)}</p>" if lead else ""
        points_html = "".join(f"<li>{inline(item)}</li>" for item in points)
        body = lead_html + (f"<ol>{points_html}</ol>" if points else "")
    return f'<section class="dimension {kind}"><h4>{label}{badge}</h4>{body}</section>'


def evidence_html(items: Iterable[Any]) -> str:
    rendered: list[str] = []
    for item in items:
        if isinstance(item, dict):
            label = item.get("label", "Evidence")
            target = item.get("target", "")
            kind = item.get("kind")
        else:
            label = target = str(item)
            kind = None
        kind_html = (
            f'<span class="evidence-kind">{html.escape(str(kind))}</span> ' if kind else ""
        )
        if re.match(r"^https?://", str(target), re.IGNORECASE):
            target_html = (
                f'<a href="{html.escape(str(target), quote=True)}" '
                f'rel="noreferrer">{inline(target)}</a>'
            )
        elif kind in ("source", "test", "decision", "spec", "document") and not any(c.isspace() for c in str(target)):
            target_html = (
                f'<a href="{html.escape(str(target), quote=True)}">'
                f'<code>{html.escape(str(target))}</code></a>'
            )
        else:
            target_html = f"<code>{html.escape(str(target))}</code>"
        rendered.append(
            f"<li>{kind_html}<span>{inline(label)}</span> {target_html}</li>"
        )
    if not rendered:
        return ""
    return (
        '<details class="evidence"><summary>Evidence</summary><ul>'
        + "".join(rendered)
        + "</ul></details>"
    )


def render_entry(entry: dict[str, Any], titles: dict[str, str]) -> str:
    entry_id = entry["id"]
    tags = entry.get("tags", [])
    badges = "".join(f'<span class="badge">{inline(tag)}</span>' for tag in tags)
    summary = (
        f'<p class="entry-summary">{inline(entry["summary"])}</p>'
        if entry.get("summary")
        else ""
    )
    synopsis = (
        f'<pre><code>{html.escape(str(entry["synopsis"]))}</code></pre>'
        if entry.get("synopsis")
        else ""
    )
    related = ""
    if entry.get("related"):
        links = " · ".join(
            f'<a href="#{html.escape(target, quote=True)}">'
            f"{inline(titles.get(target, target))}</a>"
            for target in entry["related"]
        )
        related = f'<p class="related"><strong>Related:</strong> {links}</p>'
    evidence_text = " ".join(
        f'{item.get("label", "")} {item.get("target", "")}'
        if isinstance(item, dict)
        else str(item)
        for item in entry.get("evidence", [])
    )
    searchable = " ".join(
        [
            entry.get("title", ""),
            entry.get("summary", ""),
            *tags,
            dimension_text(entry.get("what")),
            dimension_text(entry.get("how")),
            dimension_text(entry.get("why")),
            str(entry.get("why_basis", "")),
            evidence_text,
        ]
    ).lower()
    basis = basis_badge(entry.get("why_basis", ""))
    return f'''<article class="entry" id="{html.escape(entry_id, quote=True)}" data-search="{html.escape(searchable, quote=True)}">
      <div class="entry-heading"><h3>{inline(entry["title"])}</h3><a class="anchor" href="#{html.escape(entry_id, quote=True)}" aria-label="Link to this entry">#</a></div>
      <div class="badges">{badges}</div>{summary}{synopsis}
      <div class="triad">
        {render_dimension("What it does", "what", entry["what"])}
        {render_dimension("How it works", "how", entry["how"])}
        {render_dimension("Why it works this way", "why", entry["why"], basis)}
      </div>
      {evidence_html(entry.get("evidence", []))}{related}
    </article>'''


STYLE = r"""
:root{--bg:#0d1117;--panel:#161b22;--panel2:#21262d;--border:#30363d;--text:#e6edf3;--muted:#8b949e;--accent:ACCENT;--accent2:ACCENT2;--what:#38bdf8;--how:#f59e0b;--why:#3fb950;color-scheme:dark}
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:var(--bg);color:var(--text);font:16px/1.65 system-ui,-apple-system,"Segoe UI",sans-serif;display:flex;min-height:100vh}a{color:var(--accent)}code,pre{font-family:ui-monospace,SFMono-Regular,Consolas,monospace}.sidebar{width:310px;height:100vh;position:sticky;top:0;overflow:auto;flex:none;padding:1.5rem;background:var(--panel);border-right:1px solid var(--border)}.brand{display:flex;gap:.7rem;align-items:center;margin-bottom:.25rem}.brand-icon{font-size:1.7rem;color:var(--accent)}.brand h1{font-size:1.1rem;margin:0}.version{font:12px ui-monospace,monospace;color:var(--accent)}.search{width:100%;margin:1.25rem 0;padding:.65rem .75rem;border:1px solid var(--border);border-radius:7px;background:var(--bg);color:var(--text)}nav h2{margin:1.3rem 0 .35rem;font-size:.72rem;text-transform:uppercase;letter-spacing:.08em;color:var(--muted)}nav ul{list-style:none;padding:0;margin:0}nav a{display:block;padding:.3rem .45rem;text-decoration:none;color:var(--muted);font-size:.87rem;border-radius:5px}nav a:hover{color:var(--accent);background:var(--panel2)}.content{width:min(100%,1040px);padding:3.5rem 3rem 6rem;margin:0 auto}.hero h1{font-size:clamp(2.1rem,5vw,3.25rem);line-height:1.1;margin:0 0 .7rem;background:linear-gradient(120deg,var(--text),var(--accent));background-clip:text;color:transparent}.subtitle{font-size:1.2rem;color:var(--muted);margin:.2rem 0}.description{max-width:72ch}.badges{display:flex;gap:.4rem;flex-wrap:wrap;margin:.8rem 0}.badge{border:1px solid color-mix(in srgb,var(--accent) 45%,var(--border));border-radius:999px;padding:.15rem .55rem;color:var(--muted);font:12px ui-monospace,monospace}.principle{margin:2rem 0;padding:1rem 1.2rem;border-left:4px solid var(--accent);background:color-mix(in srgb,var(--accent) 8%,var(--panel));border-radius:7px}.manual-section{margin-top:4rem}.section-heading{font-size:1.8rem;padding-bottom:.5rem;border-bottom:1px solid var(--border);scroll-margin-top:1rem}.section-description{color:var(--muted)}.entry{scroll-margin-top:1rem;margin:2rem 0;padding:1.5rem;background:var(--panel);border:1px solid var(--border);border-radius:10px}.entry-heading{display:flex;align-items:center;gap:.6rem}.entry h3{margin:0;color:var(--accent);font-size:1.35rem}.anchor{text-decoration:none;opacity:0}.entry:hover .anchor,.anchor:focus{opacity:1}.entry-summary{font-size:1.05rem}.triad{display:grid;gap:1rem;grid-template-columns:repeat(3,minmax(0,1fr));margin-top:1.2rem}.dimension{padding:1rem;background:var(--bg);border-top:3px solid;border-radius:6px}.dimension h4{margin:0 0 .65rem;font-size:.78rem;text-transform:uppercase;letter-spacing:.06em}.dimension p,.dimension ol{margin:.4rem 0}.dimension ol{padding-left:1.2rem}.dimension.what{border-color:var(--what)}.dimension.what h4{color:var(--what)}.dimension.how{border-color:var(--how)}.dimension.how h4{color:var(--how)}.dimension.why{border-color:var(--why)}.dimension.why h4{color:var(--why)}pre{overflow:auto;padding:.8rem;background:#090d13;border:1px solid var(--border);border-radius:6px;color:#7ee787}.evidence{margin-top:1rem;color:var(--muted)}.evidence summary{cursor:pointer;color:var(--text)}.evidence li span{color:var(--muted);margin-right:.4rem}.related{font-size:.9rem;color:var(--muted)}.empty{display:none;padding:2rem;border:1px dashed var(--border);color:var(--muted);text-align:center}.doc-footer{margin-top:5rem;padding-top:1.5rem;border-top:1px solid var(--border);color:var(--muted);font-size:.85rem}.hidden{display:none!important}body.no-results .empty{display:block}@media(max-width:900px){body{display:block}.sidebar{position:relative;width:100%;height:auto;border-right:0;border-bottom:1px solid var(--border)}nav{display:none}.content{padding:2rem 1.15rem}.triad{grid-template-columns:1fr}}@media print{body{display:block;background:#fff;color:#111}.sidebar,.search,.anchor{display:none}.content{width:100%;padding:0}.hero h1{color:#111}.entry{break-inside:avoid;background:#fff;border-color:#bbb}.dimension{background:#fff}.badges{color:#333}}
.reviewed{margin:.35rem 0 0;font:12px ui-monospace,monospace;color:var(--muted)}.reviewed code{color:var(--muted)}.basis{display:inline-block;margin-left:.5rem;padding:.08rem .45rem;border:1px solid var(--border);border-radius:999px;font:10px ui-monospace,monospace;letter-spacing:.06em;text-transform:uppercase;color:var(--muted);vertical-align:middle}.basis-recorded{color:#3fb950}.basis-observed{color:#38bdf8}.basis-inferred{color:#f59e0b;border-style:dashed}.basis-external{color:#a855f7}.evidence-kind{display:inline-block;margin-right:.35rem;padding:.02rem .35rem;border:1px solid var(--border);border-radius:4px;font:10px ui-monospace,monospace;text-transform:uppercase;color:var(--muted)}
"""


SCRIPT = r"""
const input=document.querySelector('#manual-search');
const entries=[...document.querySelectorAll('.entry')];
const sections=[...document.querySelectorAll('.manual-section')];
input.addEventListener('input',()=>{const query=input.value.trim().toLowerCase();let visible=0;entries.forEach(entry=>{const match=!query||entry.dataset.search.includes(query);entry.classList.toggle('hidden',!match);if(match)visible++});sections.forEach(section=>section.classList.toggle('hidden',![...section.querySelectorAll('.entry')].some(entry=>!entry.classList.contains('hidden'))));document.body.classList.toggle('no-results',visible===0)});
"""


def build_html(data: dict[str, Any], wasm_payload: Optional[bytes] = None) -> str:
    project, manual = data["project"], data["manual"]
    theme = data.get("theme", {})
    accent = theme.get("accent", "#38bdf8")
    accent2 = theme.get("accent_secondary", "#a855f7")
    icon = theme.get("icon", "◇")
    titles = {
        entry["id"]: entry["title"]
        for section in data["sections"]
        for entry in section["entries"]
    }
    nav = "".join(
        f'<section><h2><a href="#{html.escape(section["id"], quote=True)}">'
        f"{inline(section['title'])}</a></h2><ul>"
        + "".join(
            f'<li><a href="#{html.escape(entry["id"], quote=True)}">'
            f"{inline(entry['title'])}</a></li>"
            for entry in section["entries"]
        )
        + "</ul></section>"
        for section in data["sections"]
    )
    sections = "".join(
        f'<section class="manual-section" id="{html.escape(section["id"], quote=True)}">'
        f'<h2 class="section-heading">{inline(section["title"])}</h2>'
        + (
            f'<p class="section-description">{inline(section["description"])}</p>'
            if section.get("description")
            else ""
        )
        + "".join(render_entry(entry, titles) for entry in section["entries"])
        + "</section>"
        for section in data["sections"]
    )
    badges = "".join(
        f'<span class="badge">{inline(badge)}</span>' for badge in manual.get("badges", [])
    )
    subtitle = (
        f'<p class="subtitle">{inline(manual["subtitle"])}</p>'
        if manual.get("subtitle")
        else ""
    )
    description = (
        f'<p class="description">{inline(manual["description"])}</p>'
        if manual.get("description")
        else ""
    )
    footer = inline(
        manual.get("footer", f'{project["name"]} {project["version"]}')
    )
    reviewed = review_metadata(manual, project)
    style = STYLE.replace("ACCENT2", str(accent2)).replace("ACCENT", str(accent))
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="generator" content="3x Documentation Scheme"><title>{html.escape(str(manual["title"]))}</title><style>{style}</style></head>
<body><aside class="sidebar"><div class="brand"><span class="brand-icon" aria-hidden="true">{inline(icon)}</span><h1>{inline(project.get("short_name", project["name"]))}</h1></div>
<div class="version">{inline(project["version"])}</div>{reviewed}<label for="manual-search" class="hidden">Search manual</label><input id="manual-search" class="search" type="search" placeholder="Search this manual…" autocomplete="off"><nav>{nav}</nav></aside>
<main class="content"><header class="hero"><h1>{inline(manual["title"])}</h1>{subtitle}{description}<div class="badges">{badges}</div>
<div class="principle"><strong>The 3x reading contract:</strong> every entry explains what it does, how it works, and why it works that way.</div></header>
<div class="empty">No entries match that search.</div>{sections}<footer class="doc-footer">{footer}</footer></main><script>{SCRIPT}</script></body></html>'''


def prepared(path: Path, overrides: list[str]) -> dict[str, Any]:
    data = load_source(path)
    for expression in overrides:
        apply_override(data, expression)
    # Resolve against a stable pre-expansion copy so replacements are deterministic.
    context = copy.deepcopy(data)
    return expand_placeholders(data, context)


def report(errors: list[str], warnings: list[str]) -> None:
    for warning in warnings:
        print(f"warning: {warning}", file=sys.stderr)
    for error in errors:
        print(f"error: {error}", file=sys.stderr)


def run_check(
    source: Path,
    overrides: list[str],
    *,
    check_evidence: bool = False,
    root: Optional[Path] = None,
    check_urls: bool = False,
    url_timeout: float = 5.0,
    json_output: bool = False,
) -> int:
    data = prepared(source, overrides)
    errors, warnings = validate(
        data,
        check_evidence=check_evidence,
        root=root,
        check_urls=check_urls,
        url_timeout=url_timeout,
    )
    passed = not errors
    if json_output:
        print(
            json.dumps(
                {
                    "command": "check",
                    "source": str(source),
                    "errors": errors,
                    "warnings": warnings,
                    "passed": passed,
                },
                indent=2,
                ensure_ascii=False,
            )
        )
    else:
        report(errors, warnings)
        if errors:
            print(
                f"check failed: {len(errors)} error(s), {len(warnings)} warning(s)",
                file=sys.stderr,
            )
        else:
            entries = sum(len(section["entries"]) for section in data["sections"])
            print(
                f"check passed: {len(data['sections'])} section(s), "
                f"{entries} entry/entries, {len(warnings)} warning(s)"
            )
    return 0 if passed else 1


def run_lint(
    source: Path,
    overrides: list[str],
    *,
    check_evidence: bool = False,
    root: Optional[Path] = None,
    check_urls: bool = False,
    url_timeout: float = 5.0,
    json_output: bool = False,
) -> int:
    data = prepared(source, overrides)
    errors, warnings = validate(
        data,
        check_evidence=check_evidence,
        root=root,
        check_urls=check_urls,
        url_timeout=url_timeout,
    )
    findings = lint_findings(data) if not errors else []
    passed = not errors and not findings
    if json_output:
        print(
            json.dumps(
                {
                    "command": "lint",
                    "source": str(source),
                    "errors": errors,
                    "warnings": warnings,
                    "findings": findings,
                    "passed": passed,
                },
                indent=2,
                ensure_ascii=False,
            )
        )
    else:
        report(errors, warnings)
        if errors:
            print("lint stopped because validation failed", file=sys.stderr)
        else:
            for finding in findings:
                label = finding["name"] + (
                    f" {finding['detail']}" if finding["detail"] else ""
                )
                print(
                    f"lint: {finding['rule']} {label}: "
                    f"{finding['location']}: {finding['snippet']}",
                    file=sys.stderr,
                )
            if findings:
                print(f"lint found {len(findings)} issue(s)", file=sys.stderr)
            else:
                entries = sum(len(section["entries"]) for section in data["sections"])
                print(f"lint passed: {entries} entry/entries, 0 issue(s)")
    return 0 if passed else 1


def run_review(
    source: Path,
    overrides: list[str],
    *,
    check_evidence: bool = False,
    root: Optional[Path] = None,
    check_urls: bool = False,
    url_timeout: float = 5.0,
    strict: bool = False,
    json_output: bool = False,
) -> int:
    data = prepared(source, overrides)
    errors, warnings, items = review(
        data,
        check_evidence=check_evidence,
        root=root,
        check_urls=check_urls,
        url_timeout=url_timeout,
    )
    passed = not errors and (not strict or not items)
    if json_output:
        print(
            json.dumps(
                {
                    "command": "review",
                    "source": str(source),
                    "errors": errors,
                    "warnings": warnings,
                    "items": items,
                    "strict": strict,
                    "passed": passed,
                },
                indent=2,
                ensure_ascii=False,
            )
        )
    else:
        report(errors, warnings)
        print(f"review: {source}")
        for item in items:
            print(f"  {item['kind']}: {item['location']}: {item['message']}")
        if errors:
            print(
                f"review failed: {len(errors)} error(s), {len(warnings)} warning(s)",
                file=sys.stderr,
            )
        else:
            print(f"review found {len(items)} item(s) for human attention")
    return 0 if passed else 1


def run_build(
    source: Path,
    output: Path,
    overrides: list[str],
    *,
    check: bool = False,
) -> int:
    data = prepared(source, overrides)
    errors, warnings = validate(data)
    report(errors, warnings)
    if errors:
        print("build stopped because validation failed", file=sys.stderr)
        return 1
    rendered = build_html(data)
    if check:
        if not output.is_file():
            print(f"build check failed: {output} is missing", file=sys.stderr)
            return 1
        existing = output.read_text(encoding="utf-8")
        if existing != rendered:
            print(f"build check failed: {output} is out of date", file=sys.stderr)
            return 1
        print(f"build check passed: {output}")
        return 0
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(rendered, encoding="utf-8")
    print(
        f"built {output} ({output.stat().st_size:,} bytes, "
        f"{len(warnings)} warning(s))"
    )
    return 0


def starter(name: str) -> dict[str, Any]:
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "my-project"
    return {
        "$schema": "scheme/manual.schema.json",
        "project": {"name": name, "short_name": name, "version": "0.1.0", "repository": ""},
        "manual": {
            "title": "{{project.name}} Manual",
            "subtitle": "Behavior, internals, and design rationale",
            "description": "A living manual for {{project.name}}.",
            "badges": ["Release {{project.version}}"],
            "footer": "{{project.name}} {{project.version}}",
        },
        "theme": {"accent": "#38bdf8", "accent_secondary": "#a855f7", "icon": "◇"},
        "sections": [
            {
                "id": "foundations",
                "title": "Foundations",
                "description": "The essential product and architecture concepts.",
                "entries": [
                    {
                        "id": f"{slug}-overview",
                        "title": f"{name} overview",
                        "summary": "The shortest useful description of this subject.",
                        "tags": ["overview"],
                        "what": "TODO: Describe observable behavior, inputs, outputs, and guarantees.",
                        "how": [
                            "TODO: Describe the execution or data flow.",
                            "Name important boundaries and failure behavior.",
                        ],
                        "why": "TODO: Explain the constraints, trade-offs, and rejected alternatives behind the design.",
                        "why_basis": "inferred",
                        "evidence": [
                            {
                                "label": "Implementation",
                                "target": "path/to/source",
                                "kind": "source",
                            }
                        ],
                        "related": [],
                    }
                ],
            }
        ],
    }


def run_init(output: Path, name: str, force: bool) -> int:
    if output.exists() and not force:
        raise ManualError(
            f"refusing to overwrite {output}; pass --force if that is intentional"
        )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(starter(name), indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(f"created {output}")
    return 0


def positive_float(value: str) -> float:
    try:
        number = float(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("must be a number") from exc
    if number <= 0:
        raise argparse.ArgumentTypeError("must be positive")
    return number


def add_diagnostic_options(item: argparse.ArgumentParser) -> None:
    item.add_argument(
        "--check-evidence",
        action="store_true",
        help="check local evidence targets",
    )
    item.add_argument(
        "--root",
        type=Path,
        default=None,
        help="project root for evidence checks",
    )
    item.add_argument(
        "--check-urls",
        action="store_true",
        help="check HTTP evidence targets",
    )
    item.add_argument(
        "--url-timeout",
        type=positive_float,
        default=5.0,
        help="timeout in seconds for URL checks",
    )
    item.add_argument(
        "--json",
        action="store_true",
        dest="json_output",
        help="emit machine-readable JSON",
    )


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Create portable What/How/Why project manuals"
    )
    commands = result.add_subparsers(dest="command", required=True)
    init = commands.add_parser("init", help="create a starter manual source")
    init.add_argument("output", type=Path)
    init.add_argument("--name", default="My Project")
    init.add_argument("--force", action="store_true")
    for command, help_text in (
        ("check", "validate a manual source"),
        ("lint", "check a manual source against the optional writing rules"),
        ("review", "report entries that need human review"),
        ("build", "build a standalone HTML manual"),
        ("watch", "rebuild when the source changes"),
    ):
        item = commands.add_parser(command, help=help_text)
        item.add_argument("source", type=Path)
        item.add_argument(
            "--set",
            action="append",
            default=[],
            metavar="PATH=VALUE",
            dest="overrides",
        )
        if command in ("check", "lint", "review"):
            add_diagnostic_options(item)
        if command in ("build", "watch"):
            item.add_argument(
                "--output", type=Path, default=Path("manual.html")
            )
        if command == "build":
            item.add_argument(
                "--check",
                action="store_true",
                help="verify OUTPUT is current without writing",
            )
        if command == "review":
            item.add_argument(
                "--strict",
                action="store_true",
                help="exit nonzero when review items exist",
            )
    return result


def main() -> int:
    args = parser().parse_args()
    try:
        if args.command == "init":
            return run_init(args.output, args.name, args.force)
        if args.command == "check":
            return run_check(
                args.source,
                args.overrides,
                check_evidence=args.check_evidence,
                root=args.root,
                check_urls=args.check_urls,
                url_timeout=args.url_timeout,
                json_output=args.json_output,
            )
        if args.command == "lint":
            return run_lint(
                args.source,
                args.overrides,
                check_evidence=args.check_evidence,
                root=args.root,
                check_urls=args.check_urls,
                url_timeout=args.url_timeout,
                json_output=args.json_output,
            )
        if args.command == "review":
            return run_review(
                args.source,
                args.overrides,
                check_evidence=args.check_evidence,
                root=args.root,
                check_urls=args.check_urls,
                url_timeout=args.url_timeout,
                strict=args.strict,
                json_output=args.json_output,
            )
        if args.command == "build":
            return run_build(
                args.source,
                args.output,
                args.overrides,
                check=args.check,
            )
        print(f"watching {args.source}; press Ctrl-C to stop")
        previous: Optional[int] = None
        while True:
            try:
                modified = args.source.stat().st_mtime_ns
                if modified != previous:
                    run_build(args.source, args.output, args.overrides)
                    previous = modified
                time.sleep(0.5)
            except FileNotFoundError:
                if previous is not None:
                    print(
                        f"waiting for {args.source} to reappear",
                        file=sys.stderr,
                    )
                    previous = None
                time.sleep(0.5)
    except KeyboardInterrupt:
        return 0
    except ManualError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
