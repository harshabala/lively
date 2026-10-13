# Sandbox and entitlement readiness

Lively is **not sandboxed** (`com.apple.security.app-sandbox` = false). Reasons:

1. The wallpaper window sits at the desktop window level, below desktop icons. The
   sandbox does not permit this window level reliably for third-party apps.
2. Per-Space identification reads the desktop picture of each Space.

Therefore the Mac App Store is not currently an option; distribution is Developer ID
plus notarization (`docs/RELEASING.md`).

## Entitlements (`entitlements.plist`)

| Entitlement | Why |
|-------------|-----|
| `files.user-selected.read-only` | Read videos the user picks. |
| `files.bookmarks.app-scope` | Persist access to those videos across launches. |

No network client, camera, microphone, location or Apple Events entitlements are
needed or requested. The hardened runtime is enabled with no exceptions.

## File-access scope

Only files the user selects (or drops) are opened, via read-only security-scoped
bookmarks. Library imports are copied into Application Support. Nothing scans the disk.

## If sandboxing becomes feasible later

Add `com.apple.security.network.client` only if the update check stays, keep the two
file entitlements, move the config folder into the container, and re-test desktop-level
window behaviour and SMAppService login items on a sandboxed build.
