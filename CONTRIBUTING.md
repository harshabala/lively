# Contributing

## Setup

Requires macOS 14+ and a Swift 6 toolchain (Xcode 26 or Command Line Tools).

```bash
swift build          # build
./test.sh            # run tests (works with Command Line Tools only)
swift test           # run tests (full Xcode)
./scripts/check_hygiene.sh   # paths, secrets, duplicates, plist and script syntax
./package.sh         # build an ad-hoc signed Lively.app (output in $LIVELY_OUTPUT_DIR)
```

`swiftlint` (config in `.swiftlint.yml`) runs in CI; run it locally if installed.

## Guidelines

- Put logic in `Sources/Lively/Logic` and test it; keep AppKit/SwiftUI thin.
- Use `LivelyBrand` tokens in UI; honour Reduce Motion and give controls accessibility labels.
- Do not add network calls, analytics or third-party dependencies. The only network
  request is the opt-in GitHub update check.
- Never log file paths or file names; use the redaction helpers.
- Never commit secrets, signing material, personal paths or Finder duplicates (`name 2.ext`).
- Add a `CHANGELOG.md` entry under Unreleased for user-visible changes.
- Small, focused commits with conventional prefixes (`feat:`, `fix:`, `docs:`, `build:`).

UI changes cannot be fully verified without Xcode and a real display; say what you
could and could not test in the pull request.
