# Privacy

Lively works entirely on your Mac.

**What is stored locally**
- Which video is assigned to which display/Space, as security-scoped bookmarks, in
  `~/Library/Application Support/Lively/`.
- Copies of videos you add to the Library, in the same folder.
- Preferences in the standard macOS preferences store, and two small usage counters
  (whether you applied a wallpaper, days active) used only to adapt first-run hints.
  They never leave your Mac.
- An in-memory log (last 1000 lines), cleared when you quit.

**What leaves your Mac**
- Nothing by default. If you turn on "Check for updates", Lively requests the public
  GitHub Releases page for this project; GitHub sees your IP address as for any web request.
  No identifiers are sent.

**Diagnostics.** "Copy Logs" and "Download Logs" create a text report you can attach to
an issue. It contains the app and macOS version, display count, a few settings and recent
log lines with home-folder paths replaced by `~`. Review it before sharing; Lively never
sends it for you.

**Removing data.** Settings > Reset Data deletes the folder above and restores preferences.
