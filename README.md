<div align="center">

<img src="docs/demo-live.png" alt="Dustnado cleaning a Windows PC in real time" width="860">

# 🌪️ Dustnado

### The smart whirlwind cleaner for Windows drives

**One file. No install. Live progress. 100% open source.**

[![Download](https://img.shields.io/badge/%E2%AC%87%20Download-Dustnado.bat-2ea44f?style=for-the-badge)](https://raw.githubusercontent.com/mr-zeel-38/dustnado/main/Dustnado.bat)
[![Star on GitHub](https://img.shields.io/badge/%E2%AD%90%20Star%20this%20repo-FFD700?style=for-the-badge&logoColor=black)](https://github.com/mr-zeel-38/dustnado)
[![Latest release](https://img.shields.io/github/v/release/mr-zeel-38/dustnado?style=for-the-badge&label=release&color=0078D6)](https://github.com/mr-zeel-38/dustnado/releases/latest)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![CI](https://github.com/mr-zeel-38/dustnado/actions/workflows/ci.yml/badge.svg)](https://github.com/mr-zeel-38/dustnado/actions/workflows/ci.yml)
[![Stars](https://img.shields.io/github/stars/mr-zeel-38/dustnado?style=flat&logo=github&color=yellow)](https://github.com/mr-zeel-38/dustnado/stargazers)
[![Forks](https://img.shields.io/github/forks/mr-zeel-38/dustnado?style=flat&logo=github)](https://github.com/mr-zeel-38/dustnado/network/members)
[![Issues](https://img.shields.io/github/issues/mr-zeel-38/dustnado?style=flat)](https://github.com/mr-zeel-38/dustnado/issues)
[![Last commit](https://img.shields.io/github/last-commit/mr-zeel-38/dustnado?style=flat)](https://github.com/mr-zeel-38/dustnado/commits/main)
[![Downloads](https://img.shields.io/github/downloads/mr-zeel-38/dustnado/total?style=flat&color=brightgreen)](https://github.com/mr-zeel-38/dustnado/releases)
![Platform](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

<sub>Demo render with simulated data - see your own results in seconds.</sub>

[**Quick start**](#-quick-start) · [**Features**](#-features) · [**Options**](#-options) · [**What it cleans**](#-what-it-cleans) · [**FAQ**](#-faq) · [**Contribute**](#-contributing)

</div>

---

## ✨ Why Dustnado?

Windows quietly piles up gigabytes of junk: update leftovers, browser caches, crash dumps, developer caches, old Windows installs. Most "cleaners" are bloated installers with ads, telemetry or upsells.

**Dustnado is a single `.bat` file you can read in five minutes.** Double-click it, watch it sweep your drives, get a clear report. That's it.

| | Dustnado | Typical cleaner |
|---|:---:|:---:|
| Install required | ❌ none | ✅ |
| Ads / telemetry / upsell | ❌ none | often |
| Source code you can read | ✅ | ❌ |
| Scan-only (delete nothing) mode | ✅ | sometimes |
| Cleans **all drives and all user profiles** | ✅ | rarely |
| Live "is it still working?" feedback | ✅ | ❌ |
| Price | **free, MIT** | freemium |

## 🚀 Quick start

1. **[⬇ Download `Dustnado.bat`](https://raw.githubusercontent.com/mr-zeel-38/dustnado/main/Dustnado.bat)** (right-click → *Save link as...*), or grab it from [Releases](https://github.com/mr-zeel-38/dustnado/releases/latest).
2. **Double-click** it and click **Yes** on the Windows admin prompt.
3. Press **ENTER** to clean, **S** to only scan, or **Q** to quit. Watch the live progress, then read the summary.

> 🛡️ **Safe by default:** if you press nothing on the start screen, Dustnado runs a **scan-only** pass after 12 seconds. Nothing is deleted unless you press **ENTER** (or start with `/yes`).

Prefer a terminal?

```bat
Dustnado.bat /scan          :: measure only, delete nothing
Dustnado.bat /yes           :: clean immediately
```

## 🌟 Features

- 🌪️ **Live UI** - overall + per-task progress bars with a **blinking head**, a pulsing **LIVE** indicator, the **current file path**, a **files-per-second activity graph**, and an ETA. If a huge item takes a while, it tells you it is *still working*.
- 💽 **All drives** - detects every fixed drive, shows live usage bars, scans them all, empties the Recycle Bin on each.
- 👥 **All users** - cleans every user profile on the PC, not just the one that launched it.
- 🧠 **Smart detection** - finds what you actually have installed (Chrome, Edge, Brave, Firefox, VS Code, Discord, CapCut, npm, pip, NuGet, Android Studio, Gradle, Docker...) and only cleans that.
- 💡 **Smart tips** - spots a huge hibernation file, big folders that could move to a roomier drive, Android/WSL/Docker disks, nearly-full drives.
- 📄 **Report** - on-screen summary plus a full `.txt` report saved to your Desktop.
- 🛡️ **Safety first** - protected-path guard, skips locked files, never follows junctions/symlinks, skips risky steps when Windows is installing updates or a restart is pending, restores any service it paused (even if you press Ctrl+C).
- ⚡ **Fast** - a native background worker handles 100,000+ files without freezing the UI.

<div align="center">
<img src="docs/demo-report.png" alt="Dustnado summary report" width="860">
</div>

## ⚙️ Options

| Option | What it does |
|---|---|
| `/scan` | **Scan only** - show what could be freed, delete nothing |
| `/yes` | Start cleaning immediately (skip the start screen) |
| `/keepbrowsers` | Don't close open browsers (their caches are partly skipped) |
| `/nodism` | Skip the Windows component-store cleanup (DISM) |
| `/deep` | Deeper DISM cleanup (`/ResetBase`) - installed Windows updates can no longer be uninstalled |
| `/help` | Show help |

```bat
Dustnado.bat /scan
Dustnado.bat /yes /keepbrowsers
```

Prefer editing? Every feature toggle lives in the **SETTINGS** block at the top of the PowerShell section inside the file.

## 🧹 What it cleans

| Area | Examples |
|---|---|
| **Temp files** | `%TEMP%` of every user, `C:\Windows\Temp` |
| **Windows Update** | Download cache, Delivery Optimization cache |
| **Crash & logs** | Crash dumps, minidumps, Windows Error Reporting, CBS/DISM/Update logs |
| **Thumbnails & shaders** | Explorer thumbnail/icon cache, NVIDIA/AMD/D3D shader caches, INetCache |
| **Browsers** | Cache, Code Cache, GPU/shader cache, Service Worker cache for Chrome, Edge, Brave, Firefox |
| **Apps** | VS Code, Cursor, Discord, Slack caches; CapCut cache; Store app temp state |
| **Developer** | npm, Yarn, pip, NuGet caches; Android Studio caches/logs; Gradle daemon logs (Gradle cache optional) |
| **Recycle Bin** | On every fixed drive |
| **Old Windows** | `Windows.old`, `$WINDOWS.~BT`, `$WINDOWS.~WS` |
| **Component store** | WinSxS cleanup via DISM (`/ResetBase` with `/deep`) |

### 🔒 What it never touches
Your **Documents, Downloads, Desktop, Pictures, Videos and Music**; browser **passwords, bookmarks, history and logins**; installed programs; and anything outside the locations listed above. Large folders it finds are only **reported** as tips - never deleted.

## 🔧 How it works

```
Dustnado.bat
 ├─ batch header   → checks Administrator rights, relaunches itself elevated (UAC)
 └─ PowerShell engine (embedded in the same file)
     ├─ native .NET worker thread  → fast scan / delete, live counters for the UI
     ├─ discovery                  → drives, user profiles, installed apps
     ├─ tasks                      → 13 cleanup steps, each safe + measurable (/scan)
     └─ UI + report                → live bars, summary, Desktop report, smart tips
```

## 📋 Requirements

- Windows 10 or Windows 11 (Windows PowerShell 5.1 - already included)
- Administrator rights (it asks)
- A terminal window of about **90 × 28** or larger (the default Windows Terminal and Command Prompt sizes work)

## ❓ FAQ

<details>
<summary><b>Is it safe?</b></summary>

It only removes caches, temp files, logs and leftovers that Windows and apps re-create. Run `/scan` first to see exactly what it finds. The source is one readable file, and every deletion goes through a protected-path guard.
</details>

<details>
<summary><b>Windows says "Windows protected your PC" (SmartScreen).</b></summary>

The file is an unsigned script downloaded from the internet. Click **More info → Run anyway** - or read the source first (it's all in one file).
</details>

<details>
<summary><b>My antivirus flagged it.</b></summary>

Scripts that delete files and compile a tiny helper (`Add-Type`) can trigger heuristic warnings. Read the code, then allow it - or don't run it if you're not comfortable.
</details>

<details>
<summary><b>Will it log me out of websites?</b></summary>

No. Cookies, logins and saved passwords are not touched. It closes your browser so the caches can be cleaned; Chrome/Edge restore your tabs when reopened. Use `/keepbrowsers` to leave browsers open.
</details>

<details>
<summary><b>Why Administrator?</b></summary>

Cleaning `C:\Windows\Temp`, the Windows Update cache, DISM and other users' profiles requires it.
</details>

<details>
<summary><b>Why did DISM take so long / get skipped?</b></summary>

The component-store cleanup can take several minutes. It is skipped automatically when updates are installing or a restart is pending - reboot and run again.
</details>

<details>
<summary><b>The layout looks cut off.</b></summary>

Maximize the window (or make it at least 90 columns wide).
</details>

## 🗺️ Roadmap

- [ ] Silent / scheduled mode (`/silent`, Task Scheduler helper)
- [ ] JSON report output for scripting
- [ ] More app caches (Teams, Zoom, Steam shader cache, Adobe media cache)
- [ ] Duplicate large-file finder (report only)
- [ ] `winget` / Scoop package
- [ ] Localized UI

Have an idea? [Open an issue](https://github.com/mr-zeel-38/dustnado/issues/new/choose).

## 🤝 Contributing

PRs are welcome - especially **new safe cleanup targets**. Please read [CONTRIBUTING.md](CONTRIBUTING.md) first, and report safety problems privately as described in [SECURITY.md](SECURITY.md).

[![Contributors](https://contrib.rocks/image?repo=mr-zeel-38/dustnado)](https://github.com/mr-zeel-38/dustnado/graphs/contributors)

## ⭐ Support the project

If Dustnado saved you some gigabytes:

- ⭐ **[Star the repo](https://github.com/mr-zeel-38/dustnado)** - it helps others find it
- 🍴 **Fork it** and add your own cleanup targets
- 🐛 **[Report a bug](https://github.com/mr-zeel-38/dustnado/issues/new/choose)** or suggest a feature
- 📣 Share it with a friend whose PC is running out of space

[![Star History Chart](https://api.star-history.com/svg?repos=mr-zeel-38/dustnado&type=Date)](https://star-history.com/#mr-zeel-38/dustnado&Date)

## ⚠️ Disclaimer

Dustnado is provided **as is**, without warranty (see the MIT license). Always keep backups of important data. Run `/scan` first if you are unsure.

## 📄 License & credit

Released under the [MIT License](LICENSE).

**Created by [Zeel Patel](https://github.com/mr-zeel-38).**

<div align="center">

**Made with 🌪️ for tidy drives** - if you like it, drop a ⭐

</div>
