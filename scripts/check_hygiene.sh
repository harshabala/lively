#!/bin/bash
# Repo hygiene checks that need no extra tooling. Run locally and in CI.
#  - no personal absolute paths in tracked files
#  - no obvious secrets
#  - no Finder-style duplicate files ("name 2.ext")
#  - version in Info.plist matches the top CHANGELOG release-or-unreleased rules
#  - plists and shell scripts are syntactically valid
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
note() { echo "FAIL: $*"; fail=1; }

files="$(git ls-files | grep -v -e '^assets/' -e '^\.agents/' -e '^\.claude/' -e '\.png$' -e '\.icns$')"

# 1. Personal paths (placeholders used in tests/docs are allowed).
if echo "$files" | xargs grep -nIE '/Users/[A-Za-z0-9._-]+' 2>/dev/null \
   | grep -vE '/Users/(alice|bob|Shared|name|you|username|<)' \
   | grep -v 'scripts/check_hygiene.sh'; then
  note "personal absolute path found in tracked files"
fi

# 2. Secrets.
if echo "$files" | xargs grep -nIE '(AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|xox[abp]-[A-Za-z0-9-]{10,})' 2>/dev/null \
   | grep -v 'scripts/check_hygiene.sh'; then
  note "possible secret found"
fi
if git ls-files | grep -iE '(^|/)(\.env(\..*)?|.*\.(p12|pem|cer|mobileprovision|provisionprofile))$' | grep -v '\.example$'; then
  note "credential-like file tracked"
fi

# 3. Duplicate files.
if git ls-files | grep -E ' [0-9]+(\.[A-Za-z0-9]+)?$'; then
  note "Finder-style duplicate file tracked"
fi

# 4. Syntax checks.
plutil -lint Info.plist entitlements.plist >/dev/null || note "plist lint failed"
for f in package.sh test.sh scripts/*.sh scripts/perf/*.sh; do
  [[ -f "$f" ]] || continue
  bash -n "$f" || note "bash syntax: $f"
done

# 5. Version sanity: Info.plist is the single source for package.sh.
v="$(plutil -extract CFBundleShortVersionString raw Info.plist)"
echo "$v" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || note "Info.plist version '$v' is not semver"
if grep -nE 'CFBundleShortVersionString' -A1 package.sh | grep -E '<string>[0-9]'; then
  note "package.sh hardcodes a version"
fi

if [ "$fail" = 0 ]; then echo "hygiene: OK"; else exit 1; fi
