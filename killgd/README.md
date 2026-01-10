# 🛑 Google Drive Killer

A bash utility to gracefully terminate Google Drive and all its related processes on macOS.

![Bash](https://img.shields.io/badge/Bash-4.0%2B-green)
![Platform](https://img.shields.io/badge/Platform-macOS-blue)
![License](https://img.shields.io/badge/License-MIT-yellow)

## 📖 Description

Sometimes Google Drive for desktop on macOS can become unresponsive or needs a complete restart. This script provides a clean, reliable way to shut down Google Drive and all its helper processes without leaving orphaned processes running in the background.

## Features

- **Graceful Shutdown**: Attempts to quit the app properly first using AppleScript
- **Complete Cleanup**: Terminates all related helper processes and extensions
- **Safe Fallback**: Uses SIGTERM first, then SIGKILL only if needed
- **Process Verification**: Confirms shutdown and reports any remaining processes
- **Targeted Killing**: Only targets Google Drive processes, not other applications

## What It Terminates

The script handles all Google Drive-related processes:

| Process | Description |
|---------|-------------|
| **Google Drive** | Main application |
| **Google Drive Helper** | Primary helper process |
| **Google Drive Helper (Renderer)** | Electron renderer processes |
| **Google Drive Helper (GPU)** | GPU acceleration processes |
| **crashpad_handler** | Crash reporting (Google Drive instances only) |
| **FinderSyncExtension** | Finder integration (Google Drive instances only) |

## Installation

```bash
# Clone or copy the script to your bin directory
cp kill-google-drive ~/bin/killgd/

# Make it executable
chmod +x ~/bin/killgd/kill-google-drive

# Add to PATH (add to ~/.zshrc or ~/.bashrc)
export PATH="$HOME/bin/killgd:$PATH"
# Command alias:
alias killgd="$HOME/bin/killgd/kill-google-drive"
```

## Usage

```bash
# Run the script directly
./kill-google-drive

# Or if added to PATH
kill-google-drive

# Or with alias
killgd
```

### Example Output

```bash
$ killgd
Shutting down Google Drive...
Google Drive has been shut down successfully
```

Or if processes remain:

```bash
$ killgd
Shutting down Google Drive...
Warning: Some Google Drive processes may still be running:
12345 Google Drive Helper (GPU)
```

## Technical Details

### Process Termination Strategy

1. **AppleScript Quit** - Asks the app to quit gracefully via `osascript`
2. **SIGTERM** - Sends termination signal to each process by exact name
3. **Wait Period** - Gives processes 0.5 seconds to clean up
4. **SIGKILL** - Forces termination if process is still running
5. **Verification** - Waits up to 3 seconds and checks for remaining processes

### Safety Features

- Uses exact process name matching (`-x` flag) to avoid killing similar processes
- Uses pattern matching for helper processes to target only Google Drive instances
- Graceful termination before forceful killing
- Silent operation when processes aren't running (no error messages)
- Final report of any processes that couldn't be terminated

### Dependencies

- **Bash** 4.0 or higher
- **macOS** with Google Drive for desktop installed
- Standard Unix utilities: `pkill`, `pgrep`, `osascript`, `kill`

### Script Options

The script uses `set -euo pipefail` for robust error handling:
- `-e` - Exit on error
- `-u` - Exit on undefined variable
- `-o pipefail` - Catch errors in piped commands

## Use Cases

### When to Use This Script

- Google Drive becomes unresponsive or frozen
- Need to restart Google Drive completely
- Before system maintenance or updates
- When Google Drive sync is stuck
- After changing Google Drive settings that require restart
- When Finder integration stops working

### Automation Examples

```bash
# Restart Google Drive completely
killgd && sleep 2 && open -a "Google Drive"

# Add to a maintenance script
#!/bin/bash
echo "Restarting Google Drive..."
killgd
sleep 3
open -a "Google Drive"
echo "Google Drive restarted"
```

### Create an Alias

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
alias gd-restart='killgd && sleep 2 && open -a "Google Drive"'
```

## Important Notes

1. **Data Safety**: This script only terminates processes. Your synced files and data are not affected.

2. **Sync Interruption**: Any ongoing uploads/downloads will be interrupted and will resume when you restart Google Drive.

3. **Graceful First**: The script always tries to quit gracefully before forcing termination.

4. **System Integration**: Finder integration will be disabled until you restart Google Drive.

5. **Permissions**: No special permissions required (runs as current user).

## Troubleshooting

### Script Reports Processes Still Running

If the script reports remaining processes:

1. Wait a few more seconds and run the script again
2. Check if Google Drive is protected by system security settings
3. Manually terminate using Activity Monitor if needed

### Google Drive Won't Start After Running

1. Wait a few seconds after termination
2. Open Google Drive from Applications folder or Spotlight
3. If issues persist, restart your Mac

## License

MIT License - Feel free to use and modify as needed.

---

**Note**: This script is designed specifically for Google Drive for desktop on macOS. It may not work with older Google Backup and Sync or on other operating systems.
