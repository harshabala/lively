# Security policy

## Reporting a vulnerability

Please use GitHub private vulnerability reporting (Security tab, "Report a
vulnerability") on this repository. Do not open a public issue for security
problems. Expect an acknowledgement within a week; this is a volunteer project.

## Supported versions

Only the latest release receives fixes.

## Threat model summary

- **Offline by design.** No account, telemetry or analytics. The only outbound
  request is the opt-in update check to the GitHub Releases API (Settings).
- **File access.** Videos are opened through user-selected files and
  security-scoped, read-only bookmarks. Lively never scans folders. Imported
  library copies live in the app's own Application Support folder.
- **Input validation.** Only `.mp4`, `.mov`, `.m4v` with H.264/HEVC tracks are accepted;
  damaged files are rejected; corrupt config files are quarantined, not trusted.
- **Not sandboxed.** The desktop-level window requires it (see `docs/SANDBOX_READINESS.md`).
  The hardened runtime is enabled and entitlements are minimal.
- **Distribution.** Release builds are currently ad-hoc signed and not notarized;
  see `docs/RELEASING.md`. Verify downloads against the SHA-256 published with the release.
- **Logs and diagnostics** never include file paths or names; exports redact home paths.
