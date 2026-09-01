#!/usr/bin/env bash
# cruft-harvest.sh - one read-only evidence dump of a codebase, for the codebase-prune workflow.
#
# Why a harvest instead of ad-hoc greps: a prune run fans out over many dimensions and many agents.
# If each one runs its own scan you get a different file universe every time, findings that
# contradict each other, and a report nobody can reconcile. Harvest once, point everyone at the
# files, and every finding is anchored to the same commit.
#
# Usage:
#   scripts/cruft-harvest.sh [repo-root] [output-dir]
#
# Examples:
#   scripts/cruft-harvest.sh . ./harvest/cruft
#   scripts/cruft-harvest.sh ../legacy-service /tmp/harvest
#
# Read-only by construction. It never writes inside the repo, never installs a tool, never runs a
# formatter or a --fix, and never runs `go mod tidy`, `npm install` or anything else that mutates a
# manifest or a lockfile. Everything lands in the output directory.
#
# A missing tool is normal and is recorded in 90-tooling.txt rather than being fatal: "vulture is
# not installed" is itself evidence, because it tells the auditor which dimensions were covered by
# a real analyser and which were covered only by grep.
#
# The file universe is `git ls-files`. That is deliberate: it gets .gitignore, vendored trees and
# build output for free, and it means every count in the report is a count of tracked files.

set -uo pipefail   # deliberately NOT -e: one absent tool must not abort the harvest

ROOT="${1:-.}"
OUT="${2:-./harvest/cruft}"

if [[ ! -d "$ROOT" ]]; then
  echo "usage: $0 [repo-root] [output-dir]" >&2
  echo "  repo-root '$ROOT' is not a directory" >&2
  exit 2
fi

mkdir -p "$OUT" || exit 2
OUT="$(cd "$OUT" && pwd)"
cd "$ROOT" || exit 2

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "error: $ROOT is not a git repository - the harvest derives its file universe from git" >&2
  exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

have() { command -v "$1" >/dev/null 2>&1; }
note() { printf '%s\n' "$*" >>"$OUT/90-tooling.txt"; }
say()  { printf '  %s\n' "$*" >&2; }

# node_modules/.bin is on the path for a JS repo without a global install.
[[ -d node_modules/.bin ]] && PATH="$PWD/node_modules/.bin:$PATH"

: >"$OUT/90-tooling.txt"
echo "harvesting $(pwd) -> $OUT" >&2

# ---------------------------------------------------------------------------
# 00 - what this is, and at which commit
# ---------------------------------------------------------------------------
{
  echo "### harvest manifest"
  echo "generated:  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "repo:       $(pwd)"
  echo "remote:     $(git remote get-url origin 2>/dev/null || echo '(none)')"
  echo "branch:     $(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  echo "head:       $(git rev-parse HEAD 2>/dev/null)"
  echo "describe:   $(git describe --tags --always --dirty 2>/dev/null)"
  echo "dirty:      $(if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then echo yes; else echo no; fi)"
  echo "tracked:    $(git ls-files | wc -l | tr -d ' ') files"
  echo "first commit: $(git log --reverse --format=%as 2>/dev/null | head -1)"
  echo "last commit:  $(git log -1 --format=%as 2>/dev/null)"
  echo "authors:      $(git log --format=%ae 2>/dev/null | sort -u | wc -l | tr -d ' ')"
} >"$OUT/00-manifest.txt"

git ls-files >"$TMP/tracked" 2>/dev/null

# Source files: tracked, minus the trees and artefacts that are never hand-edited. Everything
# downstream that says "source" means this list.
grep -vE '(^|/)(node_modules|vendor|third_party|\.venv|venv|__pycache__|dist|build|out|target|coverage|\.next|\.nuxt|Pods|DerivedData)/' "$TMP/tracked" \
  | grep -vE '(\.min\.(js|css)|\.lock|-lock\.json|\.sum|\.pbxproj|\.svg|\.png|\.jpe?g|\.gif|\.ico|\.woff2?|\.ttf|\.pdf|\.zip|\.gz)$' \
  | grep -vE '(^|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|poetry\.lock|Cargo\.lock|Gemfile\.lock|composer\.lock|go\.sum)$' \
  >"$TMP/source" 2>/dev/null
cp "$TMP/source" "$OUT/01-source-files.txt"

# ---------------------------------------------------------------------------
# 02 - inventory: what languages, what package managers, how big
# ---------------------------------------------------------------------------
{
  echo "### file count by extension (tracked source only)"
  awk -F/ '{ f = $NF; if (f ~ /\./) { n = split(f, a, "."); print a[n] } else { print "(no extension)" } }' "$TMP/source" \
    | sort | uniq -c | sort -rn | head -40
  echo
  echo "### manifests and build files present"
  for f in package.json pnpm-workspace.yaml turbo.json nx.json pyproject.toml setup.py setup.cfg \
           requirements.txt Pipfile go.mod Cargo.toml Gemfile pom.xml build.gradle build.gradle.kts \
           composer.json Package.swift mix.exs Makefile justfile Taskfile.yml Dockerfile \
           docker-bake.hcl docker-compose.yml compose.yaml .tool-versions; do
    [[ -e "$f" ]] && echo "  $f"
  done
  find . -name '*.csproj' -o -name '*.sln' -o -name '*.xcodeproj' 2>/dev/null | grep -v node_modules | head -10
  echo
  echo "### workspaces / sub-manifests (monorepo shape)"
  grep -E '(^|/)(package\.json|pyproject\.toml|go\.mod|Cargo\.toml)$' "$TMP/source" | head -60
} >"$OUT/02-inventory.txt" 2>&1

if have scc; then
  note "scc: present"
  scc --no-cocomo >"$OUT/02-loc.txt" 2>&1
  scc --by-file --sort complexity --no-cocomo 2>/dev/null | head -60 >"$OUT/07-complexity-scc.txt"
elif have tokei; then
  note "scc: MISSING (tokei used instead)"
  tokei >"$OUT/02-loc.txt" 2>&1
else
  note "scc: MISSING; tokei: MISSING (line counts are wc -l over tracked source)"
  # shellcheck disable=SC2002
  { echo "### lines per tracked source file (top 40)"; xargs wc -l <"$TMP/source" 2>/dev/null \
      | sort -rn | head -40; } >"$OUT/02-loc.txt"
fi

# ---------------------------------------------------------------------------
# 03 - entrypoints: the set a reachability tool has to be told about
# ---------------------------------------------------------------------------
{
  echo "### declared entrypoints - anything here is a root of the reachability graph"
  echo
  echo "--- container / process entrypoints"
  git grep -nE '^[[:space:]]*(ENTRYPOINT|CMD)[[:space:]]' -- '*Dockerfile*' 'Dockerfile' 2>/dev/null | head -40
  git grep -nE '^[[:space:]]*(command|args):' -- '*.yaml' '*.yml' 2>/dev/null | grep -vE '/(node_modules|vendor)/' | head -40
  echo
  echo "--- package manager scripts and binaries"
  [[ -f package.json ]] && sed -n '/"scripts"/,/}/p;/"bin"/,/[}"]/p' package.json | head -60
  [[ -f pyproject.toml ]] && sed -n '/\[project.scripts\]/,/^\[/p;/console_scripts/,/]/p' pyproject.toml | head -30
  [[ -f Makefile ]] && grep -E '^[a-zA-Z0-9_.-]+:' Makefile | head -30
  echo
  echo "--- language main functions"
  git grep -lE '^[[:space:]]*(func main\(\)|def main\(|if __name__ ==|public static void main|fn main\(\))' 2>/dev/null | head -40
  echo
  echo "--- CI workflows (each job step is an entrypoint into scripts)"
  ls -1 .github/workflows/ 2>/dev/null
  git grep -nE '^[[:space:]]*(run|uses):' -- '.github/workflows' 2>/dev/null | head -60
  echo
  echo "--- scheduled / event entrypoints"
  git grep -nE 'cron:|schedule:|lambda_handler|azure_function|CloudEvent|@app\.(route|get|post)|@router\.|@(celery|shared_task)' 2>/dev/null \
    | grep -vE '/(node_modules|vendor)/' | head -60
} >"$OUT/03-entrypoints.txt" 2>&1

# ---------------------------------------------------------------------------
# 04 - history: churn, and what nobody has touched in years
# ---------------------------------------------------------------------------
git log --since="12 months ago" --no-merges --name-only --pretty=format: 2>/dev/null \
  | grep -v '^$' | sort | uniq -c | sort -rn | head -50 >"$OUT/04-churn-12mo.txt"

# One pass over history, first (most recent) date wins, filtered to files still tracked.
git log --no-merges --pretty=format:'%as' --name-only 2>/dev/null \
  | awk -v tracked="$TMP/source" '
      BEGIN { while ((getline l < tracked) > 0) t[l] = 1 }
      /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ && NF == 1 { d = $0; next }
      NF && d != "" && ($0 in t) && !($0 in seen) { seen[$0] = 1; print d "\t" $0 }
  ' | sort >"$OUT/04-last-touched.tsv"

{
  echo "### files whose last change is oldest (candidates for 'nobody owns this any more')"
  echo "### last-change-date <TAB> path"
  head -60 "$OUT/04-last-touched.tsv"
  echo
  echo "### distribution by year of last change"
  cut -c1-4 "$OUT/04-last-touched.tsv" | sort | uniq -c | sort -k2
} >"$OUT/04-stale-files.txt" 2>&1

# ---------------------------------------------------------------------------
# 05 - dependencies: unused, undeclared, duplicated
# ---------------------------------------------------------------------------
if have knip; then
  note "knip: present"
  knip --no-exit-code --reporter compact >"$OUT/05-knip.txt" 2>&1
  knip --no-exit-code --production --reporter compact >"$OUT/05-knip-production.txt" 2>&1
else
  note "knip: MISSING (JS/TS unused files, exports and dependencies uncovered by a real analyser)"
fi
if have depcheck; then note "depcheck: present"; depcheck >"$OUT/05-depcheck.txt" 2>&1; else note "depcheck: MISSING"; fi
if have deptry;   then note "deptry: present";   deptry . >"$OUT/05-deptry.txt" 2>&1;  else note "deptry: MISSING";   fi
if have cargo && cargo machete --help >/dev/null 2>&1; then
  note "cargo-machete: present"; cargo machete >"$OUT/05-cargo-machete.txt" 2>&1
else
  note "cargo-machete: MISSING"
fi
if have go && [[ -f go.mod ]]; then
  note "go: present"
  go mod tidy -diff >"$OUT/05-go-mod-tidy-diff.txt" 2>&1   # read-only on Go >= 1.23
fi

# ---------------------------------------------------------------------------
# 06 - unreferenced symbols and files
# ---------------------------------------------------------------------------
if have vulture; then
  note "vulture: present"
  vulture --min-confidence 60 . >"$OUT/06-vulture.txt" 2>&1
  vulture --min-confidence 100 . >"$OUT/06-vulture-confident.txt" 2>&1
else
  note "vulture: MISSING (Python unreferenced symbols uncovered)"
fi
if have ruff; then
  note "ruff: present"
  ruff check --select F401,F811,F841,ARG,ERA --output-format concise . >"$OUT/06-ruff.txt" 2>&1
else
  note "ruff: MISSING"
fi
if have deadcode && [[ -f go.mod ]]; then
  note "deadcode (go): present"; deadcode ./... >"$OUT/06-go-deadcode.txt" 2>&1
else
  [[ -f go.mod ]] && note "deadcode (go): MISSING - go install golang.org/x/tools/cmd/deadcode@latest"
fi
if have staticcheck && [[ -f go.mod ]]; then
  note "staticcheck: present"; staticcheck -checks=U1000 ./... >"$OUT/06-go-staticcheck.txt" 2>&1
fi
if have periphery && ls ./*.xcodeproj ./*.xcworkspace Package.swift >/dev/null 2>&1; then
  note "periphery: present"; periphery scan --quiet >"$OUT/06-periphery.txt" 2>&1
fi
if have ts-prune; then
  note "ts-prune: present (maintenance mode - prefer knip)"
  ts-prune >"$OUT/06-ts-prune.txt" 2>&1
fi

# ---------------------------------------------------------------------------
# 07 - duplication and complexity
# ---------------------------------------------------------------------------
if have jscpd; then
  note "jscpd: present"
  jscpd --min-lines 12 --min-tokens 70 --reporters console --silent . >"$OUT/07-duplication.txt" 2>&1
else
  note "jscpd: MISSING (copy-paste blocks uncovered)"
fi
if have lizard; then
  note "lizard: present"
  lizard -C 15 -w . >"$OUT/07-complexity-lizard.txt" 2>&1
else
  note "lizard: MISSING"
fi

# Cheap structural proxies that need no tool at all.
{
  echo "### largest tracked source files (a god file is a structural finding)"
  xargs wc -l <"$TMP/source" 2>/dev/null | sort -rn | grep -v ' total$' | head -30
  echo
  echo "### directories by file count"
  sed 's#/[^/]*$##' "$TMP/source" | sort | uniq -c | sort -rn | head -30
} >"$OUT/07-size.txt" 2>&1

# ---------------------------------------------------------------------------
# 08 - the grep tier: markers a tool will not find
# ---------------------------------------------------------------------------
{
  echo "### TODO / FIXME / HACK / XXX / DEPRECATED" # DevSkim: ignore DS176209
  git grep -nE '(TODO|FIXME|HACK|XXX|DEPRECATED|@deprecated)' 2>/dev/null | grep -vE '/(node_modules|vendor|\.venv)/' | head -200 # DevSkim: ignore DS176209
  echo
  echo "### counts by marker"
  git grep -ohE '(TODO|FIXME|HACK|XXX|DEPRECATED)' 2>/dev/null | sort | uniq -c | sort -rn # DevSkim: ignore DS176209
} >"$OUT/08-todos.txt" 2>&1

{
  echo "### commented-out code (comment marker immediately followed by a code token)"
  git grep -nE '^[[:space:]]*(//|#|--|\*)[[:space:]]*(if|for|while|switch|return|import|from |def |class |func |function |const |let |var |public |private |print\(|console\.|self\.)' 2>/dev/null \
    | grep -vE '/(node_modules|vendor|\.venv)/' | head -150
  echo
  echo "### total lines matching"
  git grep -cE '^[[:space:]]*(//|#|--|\*)[[:space:]]*(if|for|while|switch|return|import|from |def |class |func |function |const |let |var |public |private )' 2>/dev/null \
    | grep -vE '/(node_modules|vendor|\.venv)/' | sort -t: -k2 -rn | head -30
} >"$OUT/08-commented-code.txt" 2>&1

{
  echo "### skipped, ignored and disabled tests"
  git grep -nE '(\.skip\(|[^a-zA-Z]xit\(|xdescribe\(|@pytest\.mark\.(skip|xfail)|@unittest\.skip|@Ignore|@Disabled|t\.Skip\(|#\[ignore\]|it\.todo\(|test\.todo\()' 2>/dev/null \
    | grep -vE '/(node_modules|vendor)/' | head -120
  echo
  echo "### test files that assert nothing (no assert/expect/should token at all)"
  while IFS= read -r f; do
    grep -qiE '(assert|expect|should|XCTAssert|verify\()' "$f" 2>/dev/null || echo "  $f"
  done < <(grep -iE '(^|/)(test|tests|spec|__tests__)/|(_test|\.test|\.spec|Test|Tests)\.' "$TMP/source" | head -400)
} >"$OUT/08-tests.txt" 2>&1

# ---------------------------------------------------------------------------
# 09 - dead configuration: env vars and feature flags
# ---------------------------------------------------------------------------
git grep -ohE '(process\.env\.[A-Z_][A-Z0-9_]*|os\.environ\[.[A-Z_][A-Z0-9_]*|os\.environ\.get\(.[A-Z_][A-Z0-9_]*|os\.getenv\(.[A-Z_][A-Z0-9_]*|getenv\("[A-Z_][A-Z0-9_]*|ENV\[.[A-Z_][A-Z0-9_]*|System\.getenv\("[A-Z_][A-Z0-9_]*)' 2>/dev/null \
  | grep -oE '[A-Z_][A-Z0-9_]{2,}' | sort -u >"$TMP/env-read"

{ git grep -ohE '^[[:space:]]*(-[[:space:]]*name:[[:space:]]*)?[A-Z_][A-Z0-9_]{2,}[[:space:]]*[:=]' \
    -- '*.env*' '.env*' '*compose*.y*ml' '.github/workflows' '*.tf' '*.yaml' '*.yml' 2>/dev/null
  cat .env.example .env.sample .env.template .env.dist 2>/dev/null
} | grep -oE '[A-Z_][A-Z0-9_]{2,}' | sort -u >"$TMP/env-declared"

{
  echo "### env vars READ by code but never DECLARED in .env*, compose, CI or IaC"
  echo "### (a missing declaration is usually a config bug, not dead code)"
  comm -23 "$TMP/env-read" "$TMP/env-declared" | sed 's/^/  /'
  echo
  echo "### env vars DECLARED but never READ by any code (dead configuration candidates)"
  echo "### expect noise here: CI shell variables and action inputs look identical to app config"
  comm -13 "$TMP/env-read" "$TMP/env-declared" | sed 's/^/  /'
  echo
  echo "### all env vars read by code"
  sed 's/^/  /' "$TMP/env-read"
} >"$OUT/09-env-vars.txt" 2>&1

{
  echo "### feature-flag references (each is a branch that may be permanently one-sided)"
  git grep -nE '(featureFlag|feature_flag|isEnabled\(|is_enabled\(|flags?\.[a-zA-Z_]|launchdarkly|LaunchDarkly|unleash|Unleash|split\.io|posthog|growthbook|FEATURE_)' 2>/dev/null \
    | grep -vE '/(node_modules|vendor)/' | head -120
} >"$OUT/09-feature-flags.txt" 2>&1

# ---------------------------------------------------------------------------
# 10 - the public surface, snapshotted so it can be diffed after the prune
# ---------------------------------------------------------------------------
git grep -nE '^[[:space:]]*(export (default |const |function |class |type |interface |enum |async )|pub (fn|struct|enum|trait|mod|const|type)|public (class|interface|enum|static|final|void|[A-Za-z<>]+ [a-zA-Z_]+\()|open (class|func|var)|func [A-Z][A-Za-z0-9_]*\(|type [A-Z][A-Za-z0-9_]* |var [A-Z][A-Za-z0-9_]* |const [A-Z][A-Za-z0-9_]* |__all__|def [a-zA-Z_][A-Za-z0-9_]*\(|class [A-Za-z_])' 2>/dev/null \
  | grep -vE '/(node_modules|vendor|\.venv|dist|build)/' | sort >"$OUT/10-public-surface.txt"

{
  echo "### total exported/public declarations: $(wc -l <"$OUT/10-public-surface.txt" | tr -d ' ')"
  echo
  echo "### is this repo a published artefact? (if yes, 'unused here' proves nothing)"
  grep -nE '"(name|version|private|publishConfig|files|exports|main|module|types)"' package.json 2>/dev/null | head -20
  grep -nE '^(name|version)|\[project\]|classifiers' pyproject.toml setup.py 2>/dev/null | head -10
  grep -nE '^module ' go.mod 2>/dev/null
  grep -nE '^(name|version|publish)' Cargo.toml 2>/dev/null | head -10
  echo
  echo "### release / publish steps in CI (a publish step means external consumers exist)"
  git grep -nE '(npm publish|twine upload|cargo publish|gh release|docker push|helm push|maven deploy)' -- '.github' 2>/dev/null | head -20
} >"$OUT/10-publish-surface.txt" 2>&1

# ---------------------------------------------------------------------------
# 11 - artefacts that should never have been committed
# ---------------------------------------------------------------------------
{
  echo "### tracked files inside build/output/dependency directories"
  grep -E '(^|/)(dist|build|out|coverage|node_modules|__pycache__|\.venv|target|DerivedData|\.pytest_cache|\.mypy_cache)/' "$TMP/tracked" | head -60
  echo
  echo "### tracked artefacts by extension"
  grep -E '\.(min\.js|min\.css|map|pyc|class|o|a|so|dylib|dll|exe|log|orig|rej|bak|swp)$|(^|/)\.DS_Store$' "$TMP/tracked" | head -60
  echo
  echo "### largest tracked files by bytes"
  xargs -n 100 wc -c <"$TMP/tracked" 2>/dev/null | awk '$2 != "total" { print $1 "\t" $2 }' | sort -rn | head -30
  echo
  echo "### files tracked despite matching a .gitignore rule"
  git ls-files --ignored --exclude-standard -c 2>/dev/null | head -40
} >"$OUT/11-artefacts.txt" 2>&1

# ---------------------------------------------------------------------------
# 12 - structure: import graph edges, for cycle and boundary analysis
# ---------------------------------------------------------------------------
git grep -nE "^[[:space:]]*(import |from |require\(|use crate::|#include \"|using )" 2>/dev/null \
  | grep -vE '/(node_modules|vendor|third_party|\.venv|dist|build|target)/' >"$TMP/imports"
IMPORT_TOTAL=$(wc -l <"$TMP/imports" | tr -d ' ')
{
  echo "### intra-repo and external import statements (source of the module graph)"
  echo "### total: $IMPORT_TOTAL"
  if [[ "$IMPORT_TOTAL" -gt 2000 ]]; then
    echo "### TRUNCATED to the first 2000 of $IMPORT_TOTAL - re-run the grep in section 12 for the rest"
  fi
  head -2000 "$TMP/imports"
} >"$OUT/12-imports.txt" 2>&1
if have madge; then
  note "madge: present"
  madge --circular --extensions ts,tsx,js,jsx . >"$OUT/12-cycles.txt" 2>&1
else
  note "madge: MISSING (import cycles uncovered for JS/TS)"
fi

# ---------------------------------------------------------------------------
# done
# ---------------------------------------------------------------------------
{
  echo
  echo "### how to read this"
  echo "A tool marked MISSING means that dimension was covered by grep only. Say so in the report."
  echo "Never install a tool into the target repo to close a gap: report the install command instead."
} >>"$OUT/90-tooling.txt"

say "wrote $(find "$OUT" -type f | wc -l | tr -d ' ') files to $OUT"
say "start with 00-manifest.txt and 90-tooling.txt"
