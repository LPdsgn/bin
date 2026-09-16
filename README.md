# 🛠️ Utility Scripts

A curated, cross-platform collection of battle-tested command-line utilities for system maintenance, security scanning, and productivity — on **macOS** (Bash) and **Windows** (PowerShell/Batch).

![Bash](https://shieldcn.dev/badge/Bash-4.0%2B-green.svg)
![PowerShell](https://shieldcn.dev/badge/PowerShell-7.0%2B-blue.svg)
![Platform](https://shieldcn.dev/badge/Platform-macOS%20%7C%20Windows-lightgrey.svg)
![License](https://shieldcn.dev/badge/License-MIT-yellow.svg)
![Scripts](https://shieldcn.dev/badge/Scripts-5-orange.svg)

## Overview

This repository (`~/.bin`) contains practical command-line tools for everyday system maintenance and WordPress security work. Each utility is self-contained, safe by default, and targets the platform(s) it was built for — some are macOS-only, some are Windows-only, and some ship a version for both.

## Available Utilities

| Utility | Platform | Purpose |
|---|---|---|
| [🧹 Disk Cleanup](cleanup/) | macOS + Linux + Windows | Interactive cache/temp-file cleaner |
| [🛑 Google Drive Killer](killgd/) | macOS | Force-quits stuck Google Drive processes |
| [🌐 My IP](myip/) | Windows | Lists local IPv4 addresses per network interface |
| [🔧 WP-CLI Wrapper](wp/) | macOS/Linux + Windows | Portable `wp-cli.phar` launcher |
| [🛡️ WP Security Scanner](wp-scan/) | Cross-platform (PowerShell) | Scans WordPress PHP/JS files for malware patterns |

---

### 🧹 [Disk Cleanup Tool](cleanup/)

Comprehensive, interactive disk space cleaner that safely removes caches and temporary files. Ships two implementations sharing the same feature set:

- `cleanup-disk` (Bash) — macOS: Xcode DerivedData, browser caches, package manager caches, Homebrew, iOS simulators, Claude Code scratchpads, and more
- `cleanup-disk-linux` (Bash) — Arch/CachyOS: BleachBit preset, uv, AUR build caches, pacman cache, Node, Docker, Gradle, Cargo
- `cleanup-disk.ps1` (PowerShell 7+) — Windows: same categories adapted for Windows, plus multi-drive selection (`-Drive C,D`, `-Drive All`)

**Quick Start:**
```bash
# macOS / Linux
cleanup-disk --dry-run         # Preview cleanup
cleanup-disk-linux --common    # Clean typical items (Linux)
```
```powershell
# Windows (pwsh)
.\cleanup-disk.ps1 -DryRun
.\cleanup-disk.ps1 -Common -Drive C
```

[📚 Full Documentation](cleanup/README.md)

---

### 🛑 [Google Drive Killer](killgd/)

Gracefully terminates Google Drive and all related processes on macOS.

**Key Features:**
- Graceful shutdown with AppleScript, falling back to SIGTERM → SIGKILL
- Terminates all helper processes, crashpad handlers, and Finder extensions
- Process verification and reporting

**Quick Start:**
```bash
killgd             # Stop Google Drive
killgd && sleep 2 && open -a "Google Drive"  # Restart
```

[📚 Full Documentation](killgd/README.md)

---

### 🌐 [My IP](myip/)

One-liner PowerShell script that lists every active IPv4 address on the machine, alongside its interface name (loopback excluded).

**Quick Start:**
```powershell
.\myip\myip.ps1
```

---

### 🔧 [WP-CLI Wrapper](wp/)

Portable [WP-CLI](https://wp-cli.org/) launcher bundling `wp-cli.phar`, so `wp` works from any shell without a separate install:

- `wp` — Bash wrapper (macOS/Linux, Cygwin-aware path translation)
- `wp.bat` — Windows Batch wrapper

**Quick Start:**
```bash
wp --info
```
```cmd
wp.bat --info
```

Requires PHP on the `PATH`.

---

### 🛡️ [WP Security Scanner](wp-scan/)

PowerShell script that recursively scans WordPress PHP/JS files for common malware and obfuscation patterns (`eval`, `base64_decode` chains, unsanitized `$_REQUEST` usage passed to `exec`/`system`, suspicious `atob`/`fromCharCode` in JS, etc.), and can export findings to a Markdown report.

**Quick Start:**
```powershell
.\wp-scan\wp-scan.ps1 -Path C:\path\to\wordpress
```

---

## 📦 Installation

### macOS

```bash
# Clone the repository
git clone https://github.com/LPdsgn/macos-scripts.git ~/.bin

# Make Bash scripts executable
chmod +x ~/.bin/cleanup/cleanup-disk ~/.bin/killgd/kill-google-drive

# Add to PATH (~/.zshrc or ~/.bashrc)
export PATH="$HOME/.bin/cleanup:$HOME/.bin/killgd:$HOME/.bin/wp:$PATH"
```

### Windows

```powershell
# Clone the repository
git clone https://github.com/LPdsgn/macos-scripts.git $HOME\.bin

# Allow running local scripts (once, per user)
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

# Add to PATH (persist via $PROFILE or System Environment Variables)
$env:PATH += ";$HOME\.bin\cleanup;$HOME\.bin\myip;$HOME\.bin\wp-scan;$HOME\.bin\wp"
```

PowerShell scripts require **PowerShell 7+** (`pwsh`, not the legacy `powershell.exe`).

## Use Cases

### For Developers
- Clean up Xcode DerivedData, iOS simulators, and Claude Code scratchpads (macOS)
- Remove Node.js, pip, Cargo, Maven/Gradle package manager caches (macOS + Windows)
- Manage WordPress installs from the CLI without a global WP-CLI install

### For Power Users
- Clean browser caches across all major browsers
- Reclaim space across multiple drives on Windows
- Check local network IPv4 addresses at a glance

### For WordPress Maintainers
- Scan themes and plugins for backdoors, obfuscated code, and suspicious patterns before/after an incident
- Export scan results to a shareable Markdown report

### For System Maintenance
- Restart an unresponsive Google Drive client
- Free up space before major OS updates
- Regular maintenance automation via scheduled tasks / cron

## 📋 Requirements

| Tool | Requirement |
|---|---|
| `cleanup-disk` (Bash) | macOS, Bash 4.0+ |
| `cleanup-disk-linux` (Bash) | Arch/CachyOS, `bleachbit`, `pacman-contrib` |
| `cleanup-disk.ps1` | Windows, PowerShell 7.0+ |
| `kill-google-drive` | macOS, Google Drive for desktop installed |
| `myip.ps1` | Windows, PowerShell 7.0+ |
| `wp` / `wp.bat` | PHP on `PATH` |
| `wp-scan.ps1` | PowerShell 7.0+ (any OS) |

All scripts run at user-level permissions — no `sudo`/admin required, except the pacman cache step of `cleanup-disk-linux`, which asks for `sudo` when you confirm it.

## 🔒 Safety & Security

All scripts follow these principles:

- ✅ **Safe by Default**: Cleanup scripts remove only regenerable caches and temporary files
- ✅ **User Confirmation**: Interactive prompts before destructive operations
- ✅ **Dry Run Mode**: Preview changes without executing them (`--dry-run` / `-DryRun`)
- ✅ **Graceful Handling**: Try gentle methods before forceful ones
- ✅ **Clear Reporting**: Detailed output with success/failure statistics
- ✅ **Read-Only Scanning**: `wp-scan` only reads files and flags patterns — it never modifies or deletes anything
- ✅ **No Sudo/Admin**: All operations run with user-level permissions

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

### Adding New Utilities

1. Create a new directory for your script
2. Follow the established pattern:
   - Bash and/or PowerShell script with clear comments
   - Safety features (dry-run, confirmations) where destructive
   - A per-tool README.md
   - Error handling and reporting
3. Test on the platform(s) you target
4. Submit a pull request

### Coding Standards

- Bash: `set -euo pipefail` for robust error handling
- PowerShell: `#Requires -Version 7.0`, typed `param()` blocks
- Implement dry-run mode for destructive operations
- Provide colored, user-friendly output
- Include help text (`--help` / `-Help`)

## License

MIT License - Feel free to use, modify, and distribute these scripts.

---

**Last updated: August 2026**
