#!/usr/bin/env python3
"""Audit a MkDocs documentation tree for drift, gaps, and broken structure.

Stdlib-only (Python 3.9+). Used by the shared `update-docs` workflow to do the
mechanical half of a docs sync, so the agent can spend its attention on the
half that needs judgement.

Checks
------
nav        nav entries with no file on disk, and pages on disk missing from nav
links      relative Markdown links and image/asset references that don't resolve
anchors    `#fragment` targets that don't match any heading on the target page
sources    pages whose `<!-- sources: ... -->` anchor points at code that has
           been committed to since the page was last touched (staleness)
stubs      pages that are empty, near-empty, or still carry TODO/TBD/FIXME
fences     fenced code blocks with no language tag
headings   pages with no H1, or with more than one H1
voice      em-dashes and banned AI-tell phrases in published prose
secrets    credential-shaped strings that must never reach a published page

Usage
-----
    python3 docs-audit.py audit
    python3 docs-audit.py audit --root . --docs docs --config mkdocs.yml
    python3 docs-audit.py audit --json --output .git/docs-audit.json
    python3 docs-audit.py audit --strict        # exit 1 on any error-level finding

Exit codes: 0 clean (or warnings only), 1 error-level findings with --strict,
2 bad invocation.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

ASSET_SUFFIXES = {
    ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp", ".ico", ".pdf",
    ".csv", ".json", ".yaml", ".yml", ".toml", ".txt", ".zip", ".drawio",
}

# Phrases banned from published prose. Mirrors the voice rules in
# shared/pr-review.md so every MagmaMoose surface reads the same way.
BANNED_PHRASES = [
    "it's worth noting", "it is worth noting", "in summary", "delve",
    "leverage", "utilize", "let's explore", "furthermore", "additionally,",
    "moreover", "it's important to note", "it is important to note",
    "seamlessly", "elevate", "unpack", "meticulously", "in today's",
    "dive into", "game-changer", "best-in-class", "cutting-edge",
]

STUB_MARKERS = ("todo", "tbd", "fixme", "coming soon", "lorem ipsum", "xxx")

PLACEHOLDER_HINTS = (
    "example", "placeholder", "your-", "your_", "<", "changeme", "change-me",
    "replace", "redacted", "dummy", "sample", "fake", "xxxx", "...", "abc123",
    "s3cret", "hunter2", "notarealkey",
)

SECRET_PATTERNS = [
    ("aws-access-key-id", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("github-token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}\b")),
    ("op-service-account-token", re.compile(r"\bops_[A-Za-z0-9]{24,}\b")),
    ("slack-token", re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}\b")),
    ("private-key-block", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("jwt", re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}")),
    (
        "assigned-credential",
        re.compile(
            r"(?i)\b(api[_-]?key|secret[_-]?key|client[_-]?secret|access[_-]?token|"
            r"auth[_-]?token|password|passwd)\b\s*[:=]\s*[\"']?([^\s\"'`<>]{12,})"
        ),
    ),
]

FENCE_RE = re.compile(r"^(\s*)(`{3,}|~{3,})(.*)$")
MD_LINK_RE = re.compile(r"(!?)\[(?:[^\]]*)\]\(\s*<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\s*\)")
HTML_SRC_RE = re.compile(r"<(?:img|a)\b[^>]*?(?:src|href)=[\"']([^\"']+)[\"']", re.IGNORECASE)
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
EXPLICIT_ANCHOR_RE = re.compile(r"\{#\s*([A-Za-z0-9_-]+)\s*\}\s*$")
SOURCES_RE = re.compile(r"<!--\s*sources?:\s*(.+?)\s*-->", re.IGNORECASE | re.DOTALL)
SETEXT_H1_RE = re.compile(r"^=+\s*$")
SETEXT_H2_RE = re.compile(r"^-{2,}\s*$")


@dataclass
class Finding:
    check: str
    level: str  # "error" | "warn" | "info"
    path: str
    line: int | None
    message: str

    def as_dict(self) -> dict:
        return {
            "check": self.check,
            "level": self.level,
            "path": self.path,
            "line": self.line,
            "message": self.message,
        }


@dataclass
class Page:
    path: Path
    rel: str
    text: str
    lines: list[str] = field(default_factory=list)
    prose_lines: list[tuple[int, str]] = field(default_factory=list)
    headings: list[tuple[int, int, str]] = field(default_factory=list)  # (line, level, text)
    anchors: set[str] = field(default_factory=set)
    sources: list[str] = field(default_factory=list)
    fences: list[tuple[int, str]] = field(default_factory=list)  # (line, info string)


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #

def slugify(value: str) -> str:
    """Approximate Python-Markdown's default toc slugify (what MkDocs uses)."""
    value = re.sub(r"`([^`]*)`", r"\1", value)
    value = re.sub(r"\*\*([^*]*)\*\*", r"\1", value)
    value = re.sub(r"\*([^*]*)\*", r"\1", value)
    value = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", value)
    value = EXPLICIT_ANCHOR_RE.sub("", value)
    value = unicodedata.normalize("NFKD", value)
    value = re.sub(r"[^\w\s-]", "", value).strip().lower()
    return re.sub(r"[-\s]+", "-", value)


def strip_frontmatter(text: str) -> tuple[str, int]:
    """Return (body, offset) with any YAML frontmatter removed."""
    if not text.startswith("---"):
        return text, 0
    lines = text.splitlines()
    for i in range(1, len(lines)):
        if lines[i].strip() in ("---", "..."):
            return "\n".join(lines[i + 1:]), i + 1
    return text, 0


def parse_config(config_path: Path) -> dict:
    """Pull the handful of keys we need out of mkdocs.yml without a YAML dep.

    Deliberately shallow: `site_name`, `docs_dir`, and every `*.md` path listed
    under `nav:`. Nav built by a plugin (awesome-pages, literate-nav) yields an
    empty list, which the nav check reports as "not statically declared" rather
    than as a pile of false orphans.
    """
    text = config_path.read_text(encoding="utf-8", errors="replace")
    out: dict = {"site_name": None, "docs_dir": "docs", "nav": None, "nav_declared": False}

    m = re.search(r"^site_name:\s*(.+?)\s*$", text, re.MULTILINE)
    if m:
        out["site_name"] = m.group(1).strip().strip("\"'")
    m = re.search(r"^docs_dir:\s*(.+?)\s*$", text, re.MULTILINE)
    if m:
        out["docs_dir"] = m.group(1).strip().strip("\"'")

    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if re.match(r"^nav:\s*(#.*)?$", line):
            start = i + 1
            break
    if start is None:
        return out

    out["nav_declared"] = True
    nav: list[str] = []
    for line in lines[start:]:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line[:1].isspace():  # a key back at column 0 ends the block
            break
        for m in re.finditer(r"([A-Za-z0-9._~/\-]+\.md)", line):
            nav.append(m.group(1))
    out["nav"] = nav
    return out


def load_page(path: Path, docs_dir: Path) -> Page:
    raw = path.read_text(encoding="utf-8", errors="replace")
    body, offset = strip_frontmatter(raw)
    lines = body.splitlines()
    page = Page(path=path, rel=str(path.relative_to(docs_dir)).replace(os.sep, "/"),
                text=body, lines=lines)

    page.sources = [
        s.strip()
        for m in SOURCES_RE.finditer(raw)
        for s in re.split(r"[,\n]", m.group(1))
        if s.strip()
    ]

    in_fence = False
    fence_marker = ""
    for idx, line in enumerate(lines, start=offset + 1):
        fm = FENCE_RE.match(line)
        if fm and (not in_fence or line.strip().startswith(fence_marker)):
            marker = fm.group(2)
            info = fm.group(3).strip()
            if not in_fence:
                in_fence, fence_marker = True, marker[:3]
                page.fences.append((idx, info))
                continue
            if not info:
                in_fence, fence_marker = False, ""
                continue
        if in_fence:
            continue

        hm = HEADING_RE.match(line)
        if hm:
            level, text_ = len(hm.group(1)), hm.group(2).strip()
            page.headings.append((idx, level, text_))
            em = EXPLICIT_ANCHOR_RE.search(text_)
            page.anchors.add(em.group(1) if em else slugify(text_))
        else:
            page.prose_lines.append((idx, line))

    # Setext headings (Title\n=====) still count as H1/H2.
    for i, line in enumerate(lines):
        prev = lines[i - 1].strip() if i else ""
        if not prev:
            continue
        if SETEXT_H1_RE.match(line):
            page.headings.append((offset + i, 1, prev))
            page.anchors.add(slugify(prev))
        elif SETEXT_H2_RE.match(line) and not prev.startswith("|"):
            page.headings.append((offset + i, 2, prev))
            page.anchors.add(slugify(prev))

    return page


def iter_links(page: Page) -> Iterable[tuple[int, str, bool]]:
    """Yield (line_no, target, is_image) for links outside fenced code."""
    in_fence = False
    for idx, line in enumerate(page.lines, start=1):
        fm = FENCE_RE.match(line)
        if fm:
            info = fm.group(3).strip()
            if not in_fence:
                in_fence = True
            elif not info:
                in_fence = False
            continue
        if in_fence:
            continue
        for m in MD_LINK_RE.finditer(line):
            yield idx, m.group(2).strip(), bool(m.group(1))
        for m in HTML_SRC_RE.finditer(line):
            yield idx, m.group(1).strip(), False


def git(root: Path, *args: str) -> str | None:
    try:
        res = subprocess.run(
            ["git", "-C", str(root), *args],
            capture_output=True, text=True, timeout=30, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if res.returncode != 0:
        return None
    return res.stdout.strip()


# --------------------------------------------------------------------------- #
# checks
# --------------------------------------------------------------------------- #

def check_nav(cfg: dict, pages: dict[str, Page], findings: list[Finding], config_rel: str) -> None:
    if cfg.get("nav") is None:
        findings.append(Finding(
            "nav", "warn", config_rel, None,
            "no static `nav:` block found; nav is plugin-generated or absent, "
            "so nav/page parity was not verified",
        ))
        return

    nav = cfg["nav"]
    seen: set[str] = set()
    for entry in nav:
        norm = entry.lstrip("./")
        if norm in seen:
            findings.append(Finding("nav", "warn", config_rel, None,
                                    f"`{norm}` is listed in nav more than once"))
        seen.add(norm)
        if norm not in pages:
            findings.append(Finding("nav", "error", config_rel, None,
                                    f"nav points at `{norm}`, which does not exist on disk"))

    for rel in sorted(pages):
        if rel in seen:
            continue
        if os.path.basename(rel) in ("README.md",):
            continue
        findings.append(Finding("nav", "error", rel, None,
                                "page exists but is not reachable from `nav:` (orphan)"))


def check_links(page: Page, docs_dir: Path, pages: dict[str, Page],
                findings: list[Finding]) -> None:
    page_dir = page.path.parent
    for line_no, target, is_image in iter_links(page):
        if not target or target.startswith(("http://", "https://", "mailto:", "tel:", "data:", "//")):
            continue
        if target.startswith("{{") or "{{" in target:  # templated by a plugin
            continue

        anchor = ""
        if "#" in target:
            target, anchor = target.split("#", 1)

        if not target:  # same-page anchor
            if anchor and anchor not in page.anchors:
                findings.append(Finding("anchors", "error", page.rel, line_no,
                                        f"`#{anchor}` matches no heading on this page"))
            continue

        if target.startswith("/"):
            findings.append(Finding("links", "warn", page.rel, line_no,
                                    f"`{target}` is site-absolute; use a relative "
                                    f"path so the site works under a sub-path"))
            resolved = (docs_dir / target.lstrip("/")).resolve()
        else:
            resolved = (page_dir / target).resolve()

        suffix = resolved.suffix.lower()
        if suffix == ".md":
            try:
                rel = str(resolved.relative_to(docs_dir.resolve())).replace(os.sep, "/")
            except ValueError:
                findings.append(Finding("links", "error", page.rel, line_no,
                                        f"`{target}` escapes the docs directory"))
                continue
            if rel not in pages:
                findings.append(Finding("links", "error", page.rel, line_no,
                                        f"link target `{target}` does not exist"))
            elif anchor and anchor not in pages[rel].anchors:
                findings.append(Finding("anchors", "error", page.rel, line_no,
                                        f"`{target}#{anchor}` matches no heading on that page"))
        elif suffix in ASSET_SUFFIXES:
            if not resolved.exists():
                kind = "image" if is_image else "asset"
                findings.append(Finding("links", "error", page.rel, line_no,
                                        f"{kind} `{target}` does not exist"))
        elif not suffix and not resolved.exists():
            findings.append(Finding("links", "warn", page.rel, line_no,
                                    f"`{target}` resolves to nothing; with "
                                    f"`use_directory_urls` prefer linking the `.md` file"))


def check_sources(page: Page, root: Path, findings: list[Finding], have_git: bool) -> None:
    if not page.sources:
        findings.append(Finding("sources", "info", page.rel, None,
                                "no `<!-- sources: ... -->` anchor; staleness for this "
                                "page can't be detected mechanically"))
        return

    missing = [s for s in page.sources if not (root / s).exists() and "*" not in s]
    for s in missing:
        findings.append(Finding("sources", "error", page.rel, None,
                                f"source anchor `{s}` no longer exists; the code this "
                                f"page documents was moved or deleted"))
    if not have_git:
        return

    live = [s for s in page.sources if s not in missing]
    if not live:
        return
    page_ts = git(root, "log", "-1", "--format=%ct", "--", str(page.path))
    if not page_ts or not page_ts.isdigit():
        return  # page is new / untracked, so there is nothing to be stale against
    log = git(root, "log", "-n", "25", "--format=%ct %h %s", "--", *live)
    if not log:
        return

    # Strictly newer only. A docs-with-the-code commit touches both in the same
    # commit at the same timestamp, and that is exactly what "in sync" looks like.
    newer = []
    for entry in log.splitlines():
        ts, _, rest = entry.partition(" ")
        if ts.isdigit() and int(ts) > int(page_ts):
            newer.append(rest)
    if newer:
        findings.append(Finding("sources", "warn", page.rel, None,
                                f"source changed after this page was last touched "
                                f"({len(newer)} commit(s), newest: {newer[0]})"))


def check_body(page: Page, findings: list[Finding], stub_words: int) -> None:
    words = len(re.findall(r"\w+", page.text))
    if words < 25:
        findings.append(Finding("stubs", "error", page.rel, None,
                                f"only {words} words; this is a placeholder, not a page"))
    elif words < stub_words:
        findings.append(Finding("stubs", "warn", page.rel, None,
                                f"only {words} words; thin for a published page, check it "
                                f"actually answers the reader's question"))

    h1s = [h for h in page.headings if h[1] == 1]
    if not h1s:
        findings.append(Finding("headings", "warn", page.rel, None,
                                "no H1; the page has no title for the nav or the ToC"))
    elif len(h1s) > 1:
        findings.append(Finding("headings", "warn", page.rel, h1s[1][0],
                                f"{len(h1s)} H1 headings; a page should have exactly one"))

    for line_no, info in page.fences:
        if not info:
            findings.append(Finding("fences", "warn", page.rel, line_no,
                                    "fenced block has no language tag (no highlighting, "
                                    "and no signal about what the reader is looking at)"))

    for line_no, line in page.prose_lines:
        low = line.lower()
        for marker in STUB_MARKERS:
            if marker in low:
                findings.append(Finding("stubs", "warn", page.rel, line_no,
                                        f"unfinished marker `{marker}` left in published prose"))
                break
        if "—" in line or "–" in line:
            findings.append(Finding("voice", "warn", page.rel, line_no,
                                    "em-dash / en-dash in published prose; use a comma, "
                                    "a colon, parentheses, or two sentences"))
        for phrase in BANNED_PHRASES:
            if phrase in low:
                findings.append(Finding("voice", "warn", page.rel, line_no,
                                        f"banned filler phrase: \"{phrase}\""))
                break


def check_secrets(page: Page, findings: list[Finding]) -> None:
    for idx, line in enumerate(page.lines, start=1):
        low = line.lower()
        for name, pattern in SECRET_PATTERNS:
            m = pattern.search(line)
            if not m:
                continue
            candidate = (m.group(2) if m.lastindex and m.lastindex >= 2 else m.group(0)).lower()
            if any(hint in candidate for hint in PLACEHOLDER_HINTS):
                continue
            if any(hint in low for hint in ("placeholder", "redact", "not a real")):
                continue
            findings.append(Finding("secrets", "error", page.rel, idx,
                                    f"credential-shaped string ({name}); published docs must "
                                    f"carry placeholders, never real values"))
            break


# --------------------------------------------------------------------------- #
# driver
# --------------------------------------------------------------------------- #

def run_audit(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    config_path = Path(args.config) if os.path.isabs(args.config) else root / args.config
    cfg = {"nav": None, "docs_dir": args.docs or "docs", "site_name": None}
    config_rel = str(config_path.relative_to(root)) if config_path.exists() else args.config

    if config_path.exists():
        cfg = parse_config(config_path)
        if args.docs:
            cfg["docs_dir"] = args.docs
    elif not args.docs:
        print(f"error: {config_path} not found and --docs not given", file=sys.stderr)
        return 2

    docs_dir = Path(cfg["docs_dir"])
    if not docs_dir.is_absolute():
        docs_dir = (config_path.parent if config_path.exists() else root) / docs_dir
    if not docs_dir.is_dir():
        print(f"error: docs directory {docs_dir} does not exist", file=sys.stderr)
        return 2

    pages: dict[str, Page] = {}
    for path in sorted(docs_dir.rglob("*.md")):
        if any(part.startswith(".") for part in path.relative_to(docs_dir).parts):
            continue
        pages[str(path.relative_to(docs_dir)).replace(os.sep, "/")] = load_page(path, docs_dir)

    findings: list[Finding] = []
    if not pages:
        findings.append(Finding("nav", "error", str(docs_dir), None, "no Markdown pages found"))

    have_git = git(root, "rev-parse", "--git-dir") is not None
    check_nav(cfg, pages, findings, config_rel)
    for page in pages.values():
        check_links(page, docs_dir, pages, findings)
        check_body(page, findings, args.stub_words)
        check_secrets(page, findings)
        if not args.no_git:
            check_sources(page, root, findings, have_git)

    order = {"error": 0, "warn": 1, "info": 2}
    findings.sort(key=lambda f: (order[f.level], f.check, f.path, f.line or 0))

    counts = {level: sum(1 for f in findings if f.level == level) for level in order}
    payload = {
        "site_name": cfg.get("site_name"),
        "docs_dir": str(docs_dir.relative_to(root)) if str(docs_dir).startswith(str(root)) else str(docs_dir),
        "pages": len(pages),
        "counts": counts,
        "findings": [f.as_dict() for f in findings],
    }

    if args.json or args.output:
        blob = json.dumps(payload, indent=2)
        if args.output:
            Path(args.output).write_text(blob + "\n", encoding="utf-8")
            print(f"wrote {args.output}")
        if args.json:
            print(blob)
    else:
        print(f"docs-audit: {len(pages)} page(s) under {payload['docs_dir']}")
        print(f"  {counts['error']} error, {counts['warn']} warn, {counts['info']} info\n")
        current = None
        for f in findings:
            if args.quiet and f.level == "info":
                continue
            if f.check != current:
                current = f.check
                print(f"[{current}]")
            where = f"{f.path}:{f.line}" if f.line else f.path
            print(f"  {f.level:<5} {where}  {f.message}")
        if not findings:
            print("  clean")

    if args.strict and counts["error"]:
        return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="docs-audit.py",
        description="Audit a MkDocs docs tree for drift, gaps, and broken structure.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    audit = sub.add_parser("audit", help="run every check over the docs tree")
    audit.add_argument("--root", default=".", help="repository root (default: .)")
    audit.add_argument("--config", default="mkdocs.yml", help="path to mkdocs.yml")
    audit.add_argument("--docs", default=None,
                       help="docs directory; overrides docs_dir from the config")
    audit.add_argument("--stub-words", type=int, default=60,
                       help="pages under this word count are flagged as stubs (default: 60)")
    audit.add_argument("--json", action="store_true", help="emit JSON on stdout")
    audit.add_argument("--output", default=None, help="write the JSON report to this path")
    audit.add_argument("--quiet", action="store_true", help="hide info-level findings")
    audit.add_argument("--no-git", action="store_true", help="skip source-anchor staleness")
    audit.add_argument("--strict", action="store_true",
                       help="exit 1 when any error-level finding is present")
    audit.set_defaults(func=run_audit)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
