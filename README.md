# 🛠️ macOS Utility Scripts

A curated collection of battle-tested bash utilities for macOS system management, maintenance, and productivity.

![Bash](https://img.shields.io/badge/Bash-4.0%2B-green)
![Platform](https://img.shields.io/badge/Platform-macOS-blue)
![License](https://img.shields.io/badge/License-MIT-yellow)
![Scripts](https://img.shields.io/badge/Scripts-2-orange)

## Overview

This repository contains practical command-line tools designed to solve common macOS pain points. Each utility is thoroughly documented, safe by default, and built with real-world usage in mind.

## Available Utilities

### 🧹 [Disk Cleanup Tool](cleanup/)

Comprehensive, interactive disk space cleaner that safely removes caches and temporary files.

**Key Features:**
- Cleans 17+ categories (browsers, dev tools, system caches)
- Interactive prompts with dry-run support
- Recovers gigabytes of space safely
- Smart detection for installed tools only

**Quick Start:**
```bash
cleanup --dry-run  # Preview cleanup
cleanup --common   # Clean typical items
```

[📚 Full Documentation](cleanup/README.md)

---

### 🛑 [Google Drive Killer](killgd/)

Gracefully terminates Google Drive and all related processes on macOS.

**Key Features:**
- Graceful shutdown with AppleScript
- Terminates all helper processes and extensions
- Safe fallback mechanisms (SIGTERM → SIGKILL)
- Process verification and reporting

**Quick Start:**
```bash
killgd             # Stop Google Drive
killgd && sleep 2 && open -a "Google Drive"  # Restart
```

[📚 Full Documentation](killgd/README.md)

---

## 📦 Installation

### Quick Install

```bash
# Clone the repository
git clone https://github.com/LPdsgn/macos-scripts.git ~/bin

# Make scripts executable
chmod +x ~/bin/cleanup/cleanup-disk
chmod +x ~/bin/killgd/kill-google-drive

# Add to PATH (optional - add to ~/.zshrc or ~/.bashrc)
export PATH="$HOME/bin/cleanup:$HOME/bin/killgd:$PATH"
```

### Individual Script Install

Each utility can be installed independently:

```bash
# Install only the cleanup tool
cp cleanup/cleanup-disk /usr/local/bin/
chmod +x /usr/local/bin/cleanup-disk

# Install only the Google Drive killer
cp killgd/kill-google-drive /usr/local/bin/
chmod +x /usr/local/bin/kill-google-drive
```

```bash
# Kill Google Drive
killgd/kill-google-drive

# Restart it
open -a "Google Drive"

# Or combine both
killgd/kill-google-drive && sleep 2 && open -a "Google Drive"
```

## Use Cases

### For Developers
- Clean up Xcode DerivedData and iOS simulators
- Remove Node.js package manager caches (npm, pnpm, yarn)
- Clear Python pip, Rust cargo, Java Maven/Gradle caches
- Reclaim space from Homebrew old versions

### For Power Users
- Clean browser caches across all major browsers
- Empty all trash folders (System, iCloud, Google Drive, Dropbox)
- Remove old system logs (30+ days)
- Clear Adobe Creative Suite media caches

### For System Maintenance
- Restart unresponsive Google Drive
- Free up space before major updates
- Regular maintenance automation

## 📋 Requirements

### System Requirements
- **OS**: macOS Monterey (12.0) or later
- **Shell**: Bash 4.0 or higher (pre-installed on macOS)
- **Permissions**: User-level (no sudo required)

## 🔒 Safety & Security

All scripts follow these principles:

- ✅ **Safe by Default**: Remove only regenerable caches and temporary files
- ✅ **User Confirmation**: Interactive prompts before destructive operations
- ✅ **Dry Run Mode**: Preview changes without executing them
- ✅ **Graceful Handling**: Try gentle methods before forceful ones
- ✅ **Clear Reporting**: Detailed output with success/failure statistics
- ✅ **Process Detection**: Check if apps are running before cleanup
- ✅ **No Sudo**: All operations run with user-level permissions

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

### Adding New Utilities

1. Create a new directory for your script
2. Follow the established pattern:
   - Bash script with clear comments
   - Safety features (dry-run, confirmations)
   - Comprehensive README.md
   - Error handling and reporting
3. Test thoroughly on multiple macOS versions
4. Submit a pull request

### Improving Existing Scripts

- Add new cleanup targets (disk cleanup)
- Improve error handling
- Add command-line options
- Enhance documentation
- Report bugs or edge cases

### Coding Standards

- Use `set -euo pipefail` for robust error handling
- Implement dry-run mode for destructive operations
- Provide colored, user-friendly output
- Include help text (`--help` flag)
- Comment complex logic
- Test on latest macOS versions

## License

MIT License - Feel free to use, modify, and distribute these scripts.

## Acknowledgments

- Built with lessons learned from real-world macOS system administration
- Inspired by the need for safe, reliable command-line tools
- Community feedback and contributions

```bash
# Verify PATH includes script directories
echo $PATH

# Add to PATH temporarily
export PATH="$HOME/bin/cleanup:$HOME/bin/killgd:$PATH"

# Add permanently to ~/.zshrc or ~/.bashrc
echo 'export PATH="$HOME/bin/cleanup:$HOME/bin/killgd:$PATH"' >> ~/.zshrc
```

## Further Reading

- [macOS Terminal User Guide](https://support.apple.com/guide/terminal/welcome/mac)
- [Bash Scripting Guide](https://www.gnu.org/software/bash/manual/)
- [Advanced Bash-Scripting Guide](https://tldp.org/LDP/abs/html/)

## Related Projects

- [mas-cli](https://github.com/mas-cli/mas) - Mac App Store command line interface
- [m-cli](https://github.com/rgcr/m-cli) - Swiss Army Knife for macOS
- [mackup](https://github.com/lra/mackup) - Keep your application settings in sync

---

**Made with ❤️ for the macOS community**

*Last updated: January 2026*
