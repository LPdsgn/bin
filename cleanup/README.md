# 🧹 macOS Disk Cleanup Tool

A comprehensive, interactive bash script for safely cleaning up disk space on macOS by removing cache files, development artifacts, and temporary data.

![Bash](https://img.shields.io/badge/Bash-4.0%2B-green)
![Platform](https://img.shields.io/badge/Platform-macOS-blue)
![License](https://img.shields.io/badge/License-MIT-yellow)

## ✨ Features

- **Safe Cleanup**: Removes only regenerable caches and temporary files
- **Interactive Mode**: Prompts for confirmation before each cleanup category
- **Dry Run Support**: Preview what would be deleted without actually removing anything
- **Smart Detection**: Only shows cleanup options for installed tools
- **Detailed Statistics**: Reports success, skipped, and failed operations
- **Color-Coded Output**: Easy-to-read terminal output with status indicators

## 🎯 What It Cleans

| Category | Items Cleaned |
|----------|---------------|
| **Development** | Xcode DerivedData, iOS DeviceSupport, Simulators |
| **Creative** | Adobe Premiere/After Effects media cache |
| **Browsers** | Chrome, Firefox, Brave, Edge, Safari caches |
| **Package Managers** | npm, pnpm, yarn, pip, Homebrew, Composer |
| **Build Tools** | Maven, Gradle, Ivy, Cargo (Rust) |
| **System** | Log files (30+ days old), Saved Application States |
| **Trash** | System Trash, Google Drive, Dropbox, iCloud |
| **Other** | Spotify, Playwright, Thunderbird, TypeScript caches |

## 📦 Installation

```bash
# Clone or copy the script to your bin directory
cp cleanup-disk ~/bin/cleanup/

# Make it executable
chmod +x ~/bin/cleanup/cleanup-disk

# Add to PATH (add to ~/.zshrc or ~/.bashrc)
export PATH="$HOME/bin/cleanup:$PATH"
# Command aliases:
alias cleanup="cleanup-disk"
alias cleanup-dry="cleanup-disk --dry-run"
alias cleanup-all="cleanup-disk --all"
```

## Usage

```bash
cleanup-disk [OPTIONS]
```

### Options

| Option | Description |
|--------|-------------|
| `-d`, `--dry-run` | Show what would be deleted without deleting |
| `-a`, `--all` | Clean everything without prompts (non-interactive) |
| `-c`, `--common` | Auto-clean common items (browsers, package managers, logs) |
| `-h`, `--help` | Show help message |

### Examples

```bash
# Interactive mode (default) - prompts for each category
cleanup-disk

# Preview what would be cleaned (recommended first run)
cleanup-disk --dry-run

# Clean common caches without prompts
cleanup-disk --common

# Full automatic cleanup (use with caution)
cleanup-disk --all

# Combine dry-run with common to preview
cleanup-disk -d -c
```

## Output Example

```
════════════════════════════════════════
  macOS Disk Cleanup Tool
════════════════════════════════════════

Current disk usage:
Used: 180G / Free: 70G (72% full)

? Clean browser caches (Chrome, Firefox, Brave, Edge)? (y/N): y
> ✓ Removing: Google caches (incl. Chrome) (1.2G)
> ✓ Removing: Firefox Cache (340M)
> ⊘ Brave Cache - Not found, skipping

════════════════════════════════════════
Cleanup complete!

Final disk usage:
Used: 178G / Free: 72G (71% full)

Space freed: ~1.5GB

Summary:
> ✓ Successfully cleaned: 12 items
> ⊘ Skipped (empty): 3 items
> ⊘ Skipped (not found): 5 items
════════════════════════════════════════
```

## Technical Details

### Dependencies

- **Required**: Bash 4.0+, macOS (tested on Monterey, Ventura, Sonoma, Sequoia)
- **Optional**: Xcode, Node.js, Python, Homebrew, Rust, Java (for respective cleanups)

### Safety Features

- Checks if applications are running before cleaning their caches
- Uses `du` to calculate sizes before deletion
- Skips empty directories automatically
- Graceful error handling with detailed failure reports
- Uses Finder AppleScript for safe Trash emptying

### Environment Variables

The script automatically sets:
- `HOMEBREW_NO_AUTO_UPDATE=1` - Prevents Homebrew from auto-updating during cleanup

## Important Notes

1. **iOS Backups**: The script can clean iOS device backups. Only use this option if you have recent iCloud or iTunes backups.

2. **Safari Cleanup**: For complete Safari cache cleanup, close Safari before running.

3. **Xcode**: Cleaning DerivedData will require rebuilding projects on next open.

4. **First Run**: Always use `--dry-run` first to see what would be deleted.

## License

MIT License - Feel free to use and modify as needed.

## Acknowledgments

Inspired by the need to reclaim disk space on development machines without manually hunting for cache directories.
