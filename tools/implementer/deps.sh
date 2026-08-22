#!/usr/bin/env bash
# Read an issue body on stdin, print one required issue number per line.
#
# Pure and offline (no `gh` calls) so it is unit-testable without network.
# Scoped to the `## Dependencies` section, and within it to only the
# `Requires ...` clause, terminated at the first period (or end of section
# if there is none). Issue bodies use the rest of the section for prose
# like "Blocks #54" or "#48 onward can then proceed" — those are NOT
# dependencies, and reading them as such would wedge the pool on issues
# that merely mention this one, not issues that gate it.
#
# Three outcomes, deliberately distinct:
#   1. No `Requires` clause at all (section absent, or present but opening
#      with something other than "Requires", e.g. "None on the sector
#      work...") -> dependency-free. Exit 0, nothing printed.
#   2. A `Requires` clause naming one or more issue numbers -> exit 0, one
#      number per line, ascending, deduplicated.
#   3. A `Requires` clause naming NO issue number (e.g. "Requires every
#      other issue in the epic.") -> UNPARSEABLE. This is NOT the same as
#      (1): there IS a dependency, we just can't name it, so the caller
#      must fail closed rather than treat it as free. Signalled by exit
#      code 2 with nothing printed on stdout, so it can never be silently
#      read as "zero dependencies" by a caller that only looks at stdout.
#      ready.sh must treat exit 2 as NOT ready.
#
# "Requires" is matched case-sensitively on purpose: every real issue body
# uses the literal capitalized word, and the only `awk` available in this
# environment is mawk, which has no case-insensitive match (that's a gawk
# extension). Digit extraction itself doesn't care about case.
set -euo pipefail

body="$(cat)"

# Extract the body of the `## Dependencies` heading: from a line that is
# exactly (ignoring trailing whitespace) "## Dependencies" up to, but not
# including, the next `## ...` heading line or end of input.
section="$(printf '%s\n' "$body" | awk '
  /^##[[:space:]]+Dependencies[[:space:]]*$/ { in_deps=1; next }
  /^##[[:space:]]/ { in_deps=0 }
  in_deps { print }
')"

if [ -z "$section" ]; then
  exit 0   # no Dependencies section at all -> dependency-free
fi

# Find the "Requires" clause: from the first literal "Requires" to the
# first "." after it (inclusive), or to the end of the section if there is
# no period. `match`/`substr`/`index` are plain POSIX awk, unlike
# IGNORECASE, so this works under mawk.
clause="$(printf '%s' "$section" | awk '
  { text = text $0 "\n" }
  END {
    n = match(text, /Requires/)
    if (n == 0) { exit 0 }
    rest = substr(text, n)
    dot = index(rest, ".")
    if (dot > 0) { rest = substr(rest, 1, dot) }
    printf "%s", rest
  }
')"

if [ -z "$clause" ]; then
  exit 0   # section present but no "Requires" clause -> dependency-free
fi

deps="$(printf '%s' "$clause" | grep -oE '#[0-9]+' | tr -d '#' | sort -un || true)"

if [ -z "$deps" ]; then
  # "Requires" present but names no issue number -> UNPARSEABLE.
  exit 2
fi

printf '%s\n' "$deps"
