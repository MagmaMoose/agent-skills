#!/usr/bin/env bash
# brag-harvest.sh - one read-only extraction of a product's brand and copy facts, for the
# brag-profile workflow.
#
# Why a harvest instead of ad-hoc greps: the facts a launch video needs - the palette, the
# fonts, the verbatim marketing copy, which screens exist - are stable for months and cheap to
# extract, but expensive to rediscover by reading source. A house design-token file is the worst
# case: every token can carry a paragraph of rationale, so `grep '^\s*--'` on it returns tens of
# thousands of tokens of prose to recover fifteen hex values. This pulls the values and drops
# the prose.
#
# Usage:
#   scripts/brag-harvest.sh [repo-root] [output-dir]
#
# Examples:
#   scripts/brag-harvest.sh . ./harvest/brag
#   scripts/brag-harvest.sh ../dunmir /tmp/brag-harvest
#
# Read-only by construction. It never writes inside the repo, never installs a tool, never runs a
# build and never starts the app. Everything lands in the output directory.
#
# A missing tool is normal and is recorded in 90-tooling.txt rather than being fatal, because
# which extractor ran tells the reader how much to trust a section.
#
# The file universe is `git ls-files`, so .gitignore, vendored trees and build output are
# excluded for free and every path in the output is a tracked path.

set -uo pipefail # deliberately NOT -e: one absent tool must not abort the harvest

ROOT="${1:-.}"
OUT="${2:-./harvest/brag}"

if [[ ! -d "$ROOT" ]]; then
  echo "usage: $0 [repo-root] [output-dir]" >&2
  echo "  repo-root '$ROOT' is not a directory" >&2
  exit 2
fi

mkdir -p "$OUT" || exit 2
OUT="$(cd "$OUT" && pwd)"
cd "$ROOT" || exit 2

TOOLING="$OUT/90-tooling.txt"
: >"$TOOLING"

note() { echo "$*" >>"$TOOLING"; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "not a git work tree: $ROOT" >&2
  exit 2
fi

FILES="$OUT/.files"
git ls-files >"$FILES" 2>/dev/null || {
  echo "git ls-files failed in $ROOT" >&2
  exit 2
}

note "repo:    $(pwd)"
note "commit:  $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
note "tracked: $(wc -l <"$FILES" | tr -d ' ') files"

HAVE_PY=0
if command -v python3 >/dev/null 2>&1; then
  HAVE_PY=1
  note "python3: $(python3 --version 2>&1)"
else
  note "python3: MISSING - token and copy extraction fall back to grep, expect noise"
fi

# --------------------------------------------------------------------------------------------
# 00-identity.txt - what the product is called and what it says it is
# --------------------------------------------------------------------------------------------
{
  echo "# Identity"
  echo
  for pkg in $(grep -E '(^|/)package\.json$' "$FILES" | grep -v node_modules | head -4); do
    [[ -f "$pkg" ]] || continue
    echo "## $pkg"
    if [[ $HAVE_PY -eq 1 ]]; then
      python3 - "$pkg" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print("  (unreadable: %s)" % e); raise SystemExit
for k in ("name", "version", "description"):
    if d.get(k):
        print("  %s: %s" % (k, d[k]))
PY
    else
      grep -E '"(name|version|description)"' "$pkg" | head -3
    fi
    echo
  done

  for html in $(grep -E '(^|/)index\.html$' "$FILES" | grep -v node_modules | head -4); do
    [[ -f "$html" ]] || continue
    echo "## $html"
    grep -oE '<title>[^<]*</title>' "$html" | head -1
    grep -oE 'name="description"[^>]*content="[^"]*"' "$html" | head -1
    grep -oE 'name="theme-color"[^>]*content="[^"]*"' "$html" | head -1
    echo
  done

  for rm in $(grep -E '(^|/)README\.md$' "$FILES" | grep -v node_modules | head -2); do
    [[ -f "$rm" ]] || continue
    echo "## $rm (first blockquote and first paragraph)"
    grep -m2 -E '^> ' "$rm"
    echo
  done
} >"$OUT/00-identity.txt" 2>/dev/null

# --------------------------------------------------------------------------------------------
# 10-tokens.txt - CSS custom properties with the rationale comments stripped
#
# This is the section that pays for the script. Values only, deduped, one per line.
# --------------------------------------------------------------------------------------------
CSSFILES="$(grep -E '\.css$' "$FILES" | grep -v -E 'node_modules|/dist/|/build/|\.min\.css$' | head -40)"
{
  echo "# CSS custom properties (comments stripped)"
  echo
  if [[ -z "$CSSFILES" ]]; then
    echo "(no tracked .css files)"
  elif [[ $HAVE_PY -eq 1 ]]; then
    # shellcheck disable=SC2086
    python3 - $CSSFILES <<'PY' 2>/dev/null
import re, sys

seen = {}
order = []
for path in sys.argv[1:]:
    try:
        src = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        continue
    # Strip /* ... */ first, including multi-line: the rationale lives there and it is
    # the whole reason a plain grep on this file is unaffordable.
    src = re.sub(r"/\*.*?\*/", " ", src, flags=re.S)
    for name, value in re.findall(r"(--[A-Za-z0-9_-]+)\s*:\s*([^;{}]+);", src):
        value = " ".join(value.split())
        if not value or len(value) > 200:
            continue
        key = (name, value)
        if key in seen:
            continue
        seen[key] = path
        order.append((name, value, path))

if not order:
    print("(no custom properties found)")
by_file = {}
for name, value, path in order:
    by_file.setdefault(path, []).append((name, value))
for path, rows in by_file.items():
    print("## %s (%d)" % (path, len(rows)))
    for name, value in rows:
        print("  %s: %s" % (name, value))
    print()
PY
  else
    for f in $CSSFILES; do
      echo "## $f"
      sed -e 's:/\*[^*]*\*/::g' "$f" | grep -oE -- '--[A-Za-z0-9_-]+\s*:\s*[^;{}]{1,200};' | head -200
      echo
    done
  fi
} >"$OUT/10-tokens.txt" 2>/dev/null

# --------------------------------------------------------------------------------------------
# 20-fonts.txt - @font-face families and the local files behind them
#
# A video should set type in the product's own faces. Self-hosted woff2 can be copied straight
# into the composition; a CDN link cannot, and the difference matters before authoring starts.
# --------------------------------------------------------------------------------------------
{
  echo "# Fonts"
  echo
  echo "## @font-face declarations"
  for f in $CSSFILES; do
    grep -q '@font-face' "$f" 2>/dev/null || continue
    echo "### $f"
    grep -A6 '@font-face' "$f" | grep -oE "(font-family:[^;]+|src:[^;]+|font-weight:[^;]+)" | head -60
    echo
  done
  echo "## Tracked font files"
  grep -E '\.(woff2?|ttf|otf)$' "$FILES" | grep -v node_modules | head -30
  echo
  echo "## Remote font references (cannot be bundled, check the CSP before using)"
  grep -rlE 'fonts\.(googleapis|gstatic)\.com' --include='*.css' --include='*.html' . 2>/dev/null |
    grep -v node_modules | head -10
  echo
  echo "## Licence files shipped with the fonts"
  grep -iE '(OFL|LICENSE)[^/]*$' "$FILES" | grep -iE 'font|OFL' | head -10
} >"$OUT/20-fonts.txt" 2>/dev/null

# --------------------------------------------------------------------------------------------
# 30-copy.txt - verbatim strings from the marketing surfaces
#
# Verbatim is the point. A launch video that paraphrases the product's own hero line reads as
# generic, and the paraphrase is usually the thing that introduces an unearned claim.
# --------------------------------------------------------------------------------------------
COPYFILES="$(grep -iE '(landing|marketing|home|hero|pricing|index)[^/]*\.(tsx|jsx|ts|js|vue|svelte|html|mdx?)$' "$FILES" |
  grep -v -E 'node_modules|\.test\.|\.spec\.|/dist/|/build/' | head -12)"
{
  echo "# Verbatim marketing copy"
  echo
  echo "Files scanned:"
  if [[ -z "$COPYFILES" ]]; then echo "  (none matched the marketing filename patterns)"; fi
  for f in $COPYFILES; do echo "  $f"; done
  echo
  if [[ $HAVE_PY -eq 1 && -n "$COPYFILES" ]]; then
    # shellcheck disable=SC2086
    python3 - $COPYFILES <<'PY' 2>/dev/null
import re, sys

# Line-based grep misses the single most valuable string in the file. A hero headline is
# routinely written across several source lines, or split by a <br />, so the whole point of
# reading it verbatim is lost exactly where it matters most. Read the file as one string.
for path in sys.argv[1:]:
    try:
        src = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        continue
    print("## %s" % path)
    if path.endswith((".md", ".mdx")):
        rows = [
            ln.strip().lstrip("#>").strip()
            for ln in src.splitlines()
            if ln.strip().startswith(("#", ">"))
        ]
    else:
        body = re.sub(r"<!--.*?-->", " ", src, flags=re.S)       # HTML comments
        body = re.sub(r"/\*.*?\*/", " ", body, flags=re.S)        # block comments
        body = re.sub(r"\{[^{}]*\}", " ", body)                   # JSX expressions
        body = re.sub(r"<br\s*/?>", " ", body, flags=re.I)        # explicit breaks join the line
        rows = []
        for raw in re.findall(r">([^<>{}]+)<", body, flags=re.S):
            text = " ".join(raw.split())
            if len(text) < 8 or len(text) > 320:
                continue
            if not re.search(r"[A-Za-z]{2,}\s+[A-Za-z]", text):   # needs two real words
                continue
            rows.append(text)
    seen = set()
    shown = 0
    for text in rows:
        if text in seen:
            continue
        seen.add(text)
        print("  " + text)
        shown += 1
        if shown >= 60:
            break
    if not shown:
        print("  (no text nodes matched)")
    print()
PY
  else
    for f in $COPYFILES; do
      [[ -f "$f" ]] || continue
      echo "## $f"
      grep -oE '>[^<>{}]{8,240}<' "$f" |
        sed -e 's/^>//' -e 's/<$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' |
        grep -E '[[:alpha:]]{2,}[[:space:]]+[[:alpha:]]' |
        awk '!seen[$0]++' | head -60
      echo
    done
  fi
} >"$OUT/30-copy.txt" 2>/dev/null

# --------------------------------------------------------------------------------------------
# 40-surfaces.txt - which screens exist, names only
#
# Names only, on purpose. The video needs to know a Dashboard and an Onboarding screen exist so
# it can pick which two to rebuild; it does not need either file's source to decide that.
# --------------------------------------------------------------------------------------------
{
  echo "# Product surfaces (names only)"
  echo
  for d in pages routes screens views app src/pages src/routes src/screens src/app \
    frontend/src/pages frontend/src/routes frontend/src/components src/components; do
    listing="$(grep -E "(^|/)${d}/[^/]+$" "$FILES" | grep -v -E '\.test\.|\.spec\.|\.stories\.' | head -60)"
    [[ -z "$listing" ]] && continue
    echo "## $d"
    echo "$listing" | sed 's:.*/::' | awk '!seen[$0]++' | paste -sd' ' -
    echo
  done
} >"$OUT/40-surfaces.txt" 2>/dev/null

# --------------------------------------------------------------------------------------------
# 50-constraints.txt - what the repo says may and may not be claimed
#
# The highest-consequence section. A launch video is public and permanent, and the rules about
# what a product is allowed to assert are usually written down in exactly one place that an
# agent reading only the landing page would never open.
# --------------------------------------------------------------------------------------------
{
  echo "# Copy and claim constraints"
  echo
  echo "## Candidate constraint modules (read these before writing any claim)"
  grep -iE '(claims?|copy|wording|legal|disclaimer|vocab)[^/]*\.(ts|tsx|js|jsx|py|json|md)$' "$FILES" |
    grep -v -E 'node_modules|\.test\.|\.spec\.' | head -20
  echo
  echo "## Exported claim constants"
  for f in $(grep -iE '(claims?|copy|wording)[^/]*\.(ts|tsx|js|jsx|py)$' "$FILES" |
    grep -v -E 'node_modules|\.test\.|\.spec\.' | head -6); do
    [[ -f "$f" ]] || continue
    echo "### $f"
    grep -nE '^(export )?(const|[A-Z_]+ ?=)' "$f" | head -30
    echo
  done
  echo "## Agent-context files that may carry hard copy rules"
  grep -iE '(^|/)(CLAUDE|AGENTS|CONTRIBUTING)\.md$' "$FILES" | head -10
  echo
  echo "## Lines in those files that read like a copy rule"
  for f in $(grep -iE '(^|/)(CLAUDE|AGENTS)\.md$' "$FILES" | head -4); do
    [[ -f "$f" ]] || continue
    grep -inE '(never (say|write|use|reach)|no em dash|must not claim|copy contains|user-facing copy|vocabulary|verbatim|identifier)' "$f" |
      head -20 | sed "s|^|  $f:|"
  done
} >"$OUT/50-constraints.txt" 2>/dev/null

rm -f "$FILES"

note ""
note "sections written:"
for f in "$OUT"/[0-9]*.txt; do
  [[ -f "$f" ]] || continue
  note "  $(basename "$f")  $(wc -l <"$f" | tr -d ' ') lines  $(wc -c <"$f" | tr -d ' ') bytes"
done

echo "brag harvest written to $OUT"
grep -E '^  [0-9]' "$TOOLING"
