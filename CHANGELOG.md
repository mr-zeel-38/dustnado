# Changelog

All notable changes to Dustnado are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/) and the project uses [Semantic Versioning](https://semver.org/).

## [1.0.1] - 2026-11-03

### Changed
- **Safer start screen:** if no key is pressed during the countdown, Dustnado now runs a **scan-only** pass (deletes nothing). Press **ENTER** to clean, or use `/yes` to start cleaning immediately.
- README rewritten with badges, quick-start buttons and a star-history chart; placeholder links fixed.

### Fixed
- `/scan` no longer follows a junction/symlink given as a cleanup item, so it cannot over-report space that lives outside the cleanup folders.

## [1.0.0] - 2026-11-03

First public release.

### Added
- One-file launcher (`Dustnado.bat`): self-elevates to Administrator, no installer, no dependencies.
- Multi-drive awareness: detects every fixed drive, shows live usage bars, scans all of them, empties the Recycle Bin on each.
- Multi-user awareness: cleans temp/browser/app/developer caches for every user profile, not just the one that launched it.
- Live UI: overall + per-task progress bars with a blinking head, pulsing LIVE indicator, current file path, files/second activity graph, ETA, and a "big item in progress" watchdog message.
- Background scan/delete worker thread (native .NET) so the UI never freezes, even on 100,000+ files.
- Smart detection of installed browsers, editors, chat apps and developer tools (Chrome, Edge, Brave, Firefox, VS Code, Discord, CapCut, npm, pip, NuGet, Android Studio, Gradle, Docker...).
- `/scan` mode: measures what could be freed and deletes nothing.
- Smart tips: hibernation file, large user folders that could move to a roomier drive, Android/WSL/Docker disks, nearly-full drives.
- Summary screen plus a full text report saved to the Desktop.
- Safety: protected-path guard, skip-if-updates-installing, skip-DISM-if-restart-pending, restores any Windows service it paused (even on Ctrl+C), never follows junctions/symlinks.
- Options: `/scan`, `/yes`, `/keepbrowsers`, `/nodism`, `/deep`, `/help`.
