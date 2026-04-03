#Requires -Version 7.0

<#
.SYNOPSIS
    Windows Disk Cleanup Script with Multi-Drive Support
.DESCRIPTION
    Safely removes cache files, development artifacts, and temporary data.
    Supports multi-drive systems with interactive drive selection.
.PARAMETER DryRun
    Show what would be deleted without deleting
.PARAMETER All
    Clean everything without prompts
.PARAMETER Common
    Clean common items without prompts (browser caches, package managers, logs)
.PARAMETER Drive
    Specify drive letter(s) to clean (e.g., -Drive C or -Drive C,D,E)
    If not specified, will prompt for drive selection
.PARAMETER Help
    Show this help message
.EXAMPLE
    .\cleanup-disk.ps1 -DryRun
    .\cleanup-disk.ps1 -All
    .\cleanup-disk.ps1 -Common
    .\cleanup-disk.ps1 -Drive C
    .\cleanup-disk.ps1 -Drive C,D -Common
    .\cleanup-disk.ps1 -Drive All -DryRun
.NOTES
    Requires PowerShell 7+. Use pwsh.exe, not powershell.exe.
    For elevated execution: gsudo pwsh -c "$HOME\.bin\cleanup\cleanup-disk.ps1 -DryRun"
#>

param(
    [Alias('d')]
    [switch]$DryRun,

    [Alias('a')]
    [switch]$All,

    [Alias('c')]
    [switch]$Common,

    [Alias('h')]
    [switch]$Help,

    [string[]]$Drive
)

# Colors for output
$Colors = @{
    Red    = 'Red'
    Green  = 'Green'
    Yellow = 'Yellow'
    Blue   = 'Cyan'
}

# Statistics tracking
$Script:Stats = @{
    Success = 0
    Skipped = 0
    Failed  = 0
    Empty   = 0
}
$Script:FailedItems = @()
$Script:DriveStats = @{}

# Show help
if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
    exit 0
}

#region Helper Functions

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = 'White'
    )
    Write-Host $Message -ForegroundColor $Color
}

function Get-FolderSize {
    param([string]$Path)

    if (-not (Test-Path $Path -ErrorAction SilentlyContinue)) {
        return "(not found)"
    }

    try {
        $job = Start-Job -ScriptBlock {
            param($p)
            (Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue |
             Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        } -ArgumentList $Path
        $completed = $job | Wait-Job -Timeout 10
        if ($null -eq $completed) {
            $job | Stop-Job; $job | Remove-Job -Force
            return "(scan timeout)"
        }
        $size = $job | Receive-Job
        $job | Remove-Job -Force

        if ($null -eq $size -or $size -eq 0) {
            return "(empty)"
        }

        if ($size -lt 1KB) { return "($size B)" }
        elseif ($size -lt 1MB) { return "($([math]::Round($size / 1KB, 1)) KB)" }
        elseif ($size -lt 1GB) { return "($([math]::Round($size / 1MB, 1)) MB)" }
        else { return "($([math]::Round($size / 1GB, 2)) GB)" }
    }
    catch {
        return "(unknown)"
    }
}

function Get-FolderSizeBytes {
    param([string]$Path)

    if (-not (Test-Path $Path -ErrorAction SilentlyContinue)) {
        return 0
    }

    try {
        $size = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        return [long]($size ?? 0)
    }
    catch {
        return 0
    }
}

function Test-IsEmpty {
    param([string]$Path)

    if (-not (Test-Path $Path -ErrorAction SilentlyContinue)) {
        return $true
    }

    try {
        $items = Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue | Select-Object -First 1
        return ($null -eq $items)
    }
    catch {
        return $true
    }
}

function Test-ProcessRunning {
    param([string]$ProcessName)
    return $null -ne (Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
}

function Test-CommandExists {
    param([string]$Command)
    return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Remove-SafePath {
    param(
        [string]$Path,
        [string]$Description,
        [string]$Context = ""
    )

    try {
        $exists = Test-Path $Path -ErrorAction Stop
    }
    catch {
        Write-Host "> " -NoNewline
        Write-Host ([char]0x2298) -ForegroundColor Yellow -NoNewline
        Write-Host " $Description - Access denied, skipping"
        $Script:Stats.Skipped++
        return
    }

    if (-not $exists) {
        Write-Host "> " -NoNewline
        Write-Host ([char]0x2298) -ForegroundColor Yellow -NoNewline
        Write-Host " $Description - Not found, skipping"
        $Script:Stats.Skipped++
        return
    }

    if (Test-IsEmpty $Path) {
        Write-Host "> " -NoNewline
        Write-Host ([char]0x2298) -ForegroundColor Yellow -NoNewline
        Write-Host " $Description (empty)"
        $Script:Stats.Empty++
        return
    }

    $size = Get-FolderSize $Path

    if ($DryRun) {
        Write-Host "> " -NoNewline
        Write-Host "[DRY RUN]" -ForegroundColor Cyan -NoNewline
        Write-Host " Would delete: $Description $size"
        $Script:Stats.Success++
    }
    else {
        Write-Host "> " -NoNewline
        Write-Host ([char]0x2713) -ForegroundColor Green -NoNewline
        Write-Host " Removing: $Description $size"

        try {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
            $Script:Stats.Success++
        }
        catch {
            $errorMsg = if ($Context) { $Context } else { "permission denied or in use" }
            Write-Host "> " -NoNewline
            Write-Host ([char]0x2717) -ForegroundColor Red -NoNewline
            Write-Host " Error: Could not remove $Description - $errorMsg"
            $Script:FailedItems += "$Description - $errorMsg"
            $Script:Stats.Failed++
        }
    }
}

function Confirm-Action {
    param([string]$Message)

    if ($All) { return $true }
    if ($Common) { return $false }

    Write-Host "? " -ForegroundColor Yellow -NoNewline
    $response = Read-Host "$Message (y/N)"
    return $response -match '^[yY]'
}

function Confirm-CommonAction {
    param([string]$Message)

    if ($Common -or $All) { return $true }
    return Confirm-Action $Message
}

function Format-ByteSize {
    param([long]$Bytes)

    if ($Bytes -lt 0) { $Bytes = 0 }
    if ($Bytes -lt 1KB) { return "${Bytes}B" }
    elseif ($Bytes -lt 1MB) { return "$([math]::Round($Bytes / 1KB, 1))KB" }
    elseif ($Bytes -lt 1GB) { return "$([math]::Round($Bytes / 1MB, 1))MB" }
    else { return "$([math]::Round($Bytes / 1GB, 2))GB" }
}

function Get-AvailableDrives {
    <#
    .SYNOPSIS
        Get all available fixed drives with user profiles or cleanable data
    #>
    $drives = [System.Collections.ArrayList]::new()

    # Get all fixed drives (using Get-CimInstance for PowerShell 7+ compatibility)
    Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
        $driveLetter = $_.DeviceID.TrimEnd(':')
        $driveInfo = [PSCustomObject]@{
            Letter      = $driveLetter
            Label       = if ($_.VolumeName) { $_.VolumeName } else { "Local Disk" }
            TotalGB     = [math]::Round($_.Size / 1GB, 2)
            FreeGB      = [math]::Round($_.FreeSpace / 1GB, 2)
            UsedGB      = [math]::Round(($_.Size - $_.FreeSpace) / 1GB, 2)
            PercentUsed = [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 1)
            HasUsers    = (Test-Path "${driveLetter}:\Users")
            HasWindows  = (Test-Path "${driveLetter}:\Windows")
            HasPrograms = (Test-Path "${driveLetter}:\Program Files") -or (Test-Path "${driveLetter}:\Program Files (x86)")
            FreeSpace   = $_.FreeSpace
        }
        [void]$drives.Add($driveInfo)
    }

    return $drives
}

function Show-DriveSelection {
    param([array]$Drives)

    Write-Host ""
    Write-Host "Available drives:" -ForegroundColor Cyan
    Write-Host ("-" * 85)
    Write-Host ("{0,-8} {1,-22} {2,-12} {3,-12} {4,-10} {5}" -f "Drive", "Label", "Total", "Free", "Used %", "Contents")
    Write-Host ("-" * 85)

    $index = 1
    foreach ($drv in $Drives) {
        $contents = @()
        if ($drv.HasWindows) { $contents += "Windows" }
        if ($drv.HasUsers) { $contents += "Users" }
        if ($drv.HasPrograms) { $contents += "Programs" }
        $contentsStr = $contents -join ", "

        # Truncate long labels
        $label = $drv.Label
        if ($label.Length -gt 20) {
            $label = $label.Substring(0, 17) + "..."
        }

        $usedColor = if ($drv.PercentUsed -gt 90) { "Red" } elseif ($drv.PercentUsed -gt 70) { "Yellow" } else { "White" }

        Write-Host ("{0,-8}" -f "[$index] $($drv.Letter):") -NoNewline
        Write-Host ("{0,-22}" -f $label) -NoNewline
        Write-Host ("{0,-12}" -f "$($drv.TotalGB) GB") -NoNewline
        Write-Host ("{0,-12}" -f "$($drv.FreeGB) GB") -NoNewline
        Write-Host ("{0,-10}" -f "$($drv.PercentUsed)%") -ForegroundColor $usedColor -NoNewline
        Write-Host $contentsStr
        $index++
    }

    Write-Host ("-" * 85)
    Write-Host "[A] All drives" -ForegroundColor Green
    Write-Host "[Q] Quit" -ForegroundColor Red
    Write-Host ""
}

function Get-UserSelection {
    param([array]$Drives)

    while ($true) {
        Write-Host "? " -ForegroundColor Yellow -NoNewline
        $selection = Read-Host "Select drive(s) to clean (e.g., 1, 1,2,3, or A for all)"

        if ($selection -match '^[Qq]$') {
            Write-Host "Operation cancelled." -ForegroundColor Yellow
            exit 0
        }

        if ($selection -match '^[Aa]$') {
            return $Drives.Letter
        }

        # Parse numeric selections
        $selectedDrives = @()
        $parts = $selection -split '[,\s]+'

        foreach ($part in $parts) {
            if ($part -match '^\d+$') {
                $idx = [int]$part - 1
                if ($idx -ge 0 -and $idx -lt $Drives.Count) {
                    $selectedDrives += $Drives[$idx].Letter
                }
                else {
                    Write-Host "Invalid selection: $part" -ForegroundColor Red
                    continue
                }
            }
            elseif ($part -match '^[A-Za-z]$') {
                # Direct drive letter
                $letter = $part.ToUpper()
                if ($Drives.Letter -contains $letter) {
                    $selectedDrives += $letter
                }
                else {
                    Write-Host "Drive $letter not found" -ForegroundColor Red
                }
            }
        }

        if ($selectedDrives.Count -gt 0) {
            return $selectedDrives | Select-Object -Unique
        }

        Write-Host "No valid drives selected. Please try again." -ForegroundColor Red
    }
}

function Get-UserProfilesOnDrive {
    param([string]$DriveLetter)

    $profiles = @()
    $usersPath = "${DriveLetter}:\Users"

    if (Test-Path $usersPath -ErrorAction SilentlyContinue) {
        Get-ChildItem -Path $usersPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            # Skip system folders
            if ($_.Name -notin @('Public', 'Default', 'Default User', 'All Users')) {
                try {
                    if (Test-Path "$($_.FullName)\AppData" -ErrorAction Stop) {
                        $profiles += @{
                            Name        = $_.Name
                            Path        = $_.FullName
                            AppData     = "$($_.FullName)\AppData\Roaming"
                            LocalAppData = "$($_.FullName)\AppData\Local"
                            Temp        = "$($_.FullName)\AppData\Local\Temp"
                        }
                    }
                }
                catch {
                    # Skip profiles we can't access (e.g. Administrator, DefaultAppPool)
                }
            }
        }
    }

    return $profiles
}

#endregion

#region Main Script

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "  Windows Disk Cleanup Tool - Multi-Drive Edition" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host ""

if ($DryRun) {
    Write-Host "Running in DRY RUN mode - nothing will be deleted" -ForegroundColor Yellow
    Write-Host ""
}

if ($Common) {
    Write-Host "Running with -Common flag (cleaning typical items)" -ForegroundColor Cyan
    Write-Host ""
}

# Get available drives
$AvailableDrives = Get-AvailableDrives

if ($AvailableDrives.Count -eq 0) {
    Write-Host "No drives found!" -ForegroundColor Red
    exit 1
}

# Determine which drives to clean
$SelectedDriveLetters = @()

if ($Drive) {
    # Drive(s) specified via parameter
    if ($Drive -contains "All" -or $Drive -contains "all") {
        $SelectedDriveLetters = $AvailableDrives.Letter
    }
    else {
        foreach ($d in $Drive) {
            $letter = $d.TrimEnd(':').ToUpper()
            if ($AvailableDrives.Letter -contains $letter) {
                $SelectedDriveLetters += $letter
            }
            else {
                Write-Host "Warning: Drive $letter not found, skipping" -ForegroundColor Yellow
            }
        }
    }
}
else {
    # Interactive drive selection
    Show-DriveSelection -Drives $AvailableDrives
    $SelectedDriveLetters = Get-UserSelection -Drives $AvailableDrives
}

if ($SelectedDriveLetters.Count -eq 0) {
    Write-Host "No valid drives selected. Exiting." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Selected drives: " -NoNewline -ForegroundColor Cyan
Write-Host ($SelectedDriveLetters -join ", ") -ForegroundColor Green
Write-Host ""

# Show initial disk usage for selected drives
Write-Host "Current disk usage:" -ForegroundColor Cyan
$TotalFreeBefore = @{}

foreach ($letter in $SelectedDriveLetters) {
    $driveInfo = $AvailableDrives | Where-Object { $_.Letter -eq $letter }
    if ($driveInfo) {
        $usedColor = if ($driveInfo.PercentUsed -gt 90) { "Red" } elseif ($driveInfo.PercentUsed -gt 70) { "Yellow" } else { "White" }
        Write-Host "  ${letter}: " -NoNewline
        Write-Host "Used: $($driveInfo.UsedGB)GB / Free: $($driveInfo.FreeGB)GB " -NoNewline
        Write-Host "($($driveInfo.PercentUsed)% full)" -ForegroundColor $usedColor
        $TotalFreeBefore[$letter] = $driveInfo.FreeSpace
    }
}
Write-Host ""

# Initialize per-drive stats
foreach ($letter in $SelectedDriveLetters) {
    $Script:DriveStats[$letter] = @{
        Success = 0
        Skipped = 0
        Failed  = 0
        Empty   = 0
    }
}

#region Cleanup Operations

# Process each selected drive
foreach ($currentDrive in $SelectedDriveLetters) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Magenta
    Write-Host "  Cleaning Drive ${currentDrive}:" -ForegroundColor Magenta
    Write-Host ("=" * 60) -ForegroundColor Magenta
    Write-Host ""

    # Get user profiles on this drive
    $UserProfiles = Get-UserProfilesOnDrive -DriveLetter $currentDrive

    # Set paths for current drive
    $DriveRoot = "${currentDrive}:"
    $WindowsPath = "${currentDrive}:\Windows"
    $ProgramFilesPath = "${currentDrive}:\Program Files"
    $ProgramFilesX86Path = "${currentDrive}:\Program Files (x86)"
    $ProgramDataPath = "${currentDrive}:\ProgramData"

    # Check if this is the system drive
    $IsSystemDrive = (Test-Path $WindowsPath)

    # ==========================================
    # SYSTEM-WIDE CLEANUP (only on system drive)
    # ==========================================

    if ($IsSystemDrive) {
        Write-Host "[System Drive Cleanup]" -ForegroundColor Cyan
        Write-Host ""

        # 1. System Temp Files
        if (Confirm-CommonAction "Clean System Temp files on ${currentDrive}:?") {
            Remove-SafePath "$WindowsPath\Temp" "System Temp folder"
        }

        # 2. Windows Update Cache
        if (Confirm-Action "Clean Windows Update cache on ${currentDrive}: (requires admin)?") {
            Remove-SafePath "$WindowsPath\SoftwareDistribution\Download" "Windows Update Download Cache" "May require administrator rights"
        }

        # 3. Windows Prefetch
        if (Confirm-Action "Clean Windows Prefetch files on ${currentDrive}: (requires admin)?") {
            Remove-SafePath "$WindowsPath\Prefetch" "Windows Prefetch" "May require administrator rights"
        }

        # 4. Windows.old folder
        if (Test-Path "${currentDrive}:\Windows.old") {
            if (Confirm-Action "Delete Windows.old on ${currentDrive}: (previous Windows - CANNOT UNDO)?") {
                Write-Host "> " -NoNewline
                Write-Host "Warning:" -ForegroundColor Red -NoNewline
                Write-Host " This removes your ability to roll back to previous Windows version!"

                if (-not $DryRun) {
                    try {
                        Remove-Item -Path "${currentDrive}:\Windows.old" -Recurse -Force -ErrorAction Stop
                        $Script:Stats.Success++
                    }
                    catch {
                        Write-Host "> " -NoNewline
                        Write-Host "Note:" -ForegroundColor Yellow -NoNewline
                        Write-Host " Use Disk Cleanup > Clean up system files > Previous Windows installation"
                        $Script:Stats.Skipped++
                    }
                }
                else {
                    $size = Get-FolderSize "${currentDrive}:\Windows.old"
                    Write-Host "> [DRY RUN] Would delete: Windows.old $size" -ForegroundColor Cyan
                    $Script:Stats.Success++
                }
            }
        }

        # 5. Delivery Optimization
        if (Confirm-CommonAction "Clean Delivery Optimization files on ${currentDrive}:?") {
            Remove-SafePath "$WindowsPath\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache" "Delivery Optimization Cache" "May require admin"
        }

        # 6. Windows Error Reporting (System)
        if (Confirm-CommonAction "Clean Windows Error Reporting on ${currentDrive}:?") {
            Remove-SafePath "$ProgramDataPath\Microsoft\Windows\WER" "Windows Error Reports (System)"
            if (Test-Path "$WindowsPath\MEMORY.DMP") {
                Remove-SafePath "$WindowsPath\MEMORY.DMP" "System Memory Dump" "May require admin"
            }
            if (Test-Path "$WindowsPath\Minidump") {
                Remove-SafePath "$WindowsPath\Minidump" "Minidump Files" "May require admin"
            }
        }

        # 7. Windows Defender
        if (Confirm-Action "Clean Windows Defender cache on ${currentDrive}:?") {
            Remove-SafePath "$ProgramDataPath\Microsoft\Windows Defender\Scans\History" "Defender Scan History" "May require admin"
            Remove-SafePath "$ProgramDataPath\Microsoft\Windows Defender\Scans\MetaStore" "Defender MetaStore"
        }

        # 8. WinSxS Component Cleanup
        if (Confirm-Action "Clean Windows Component Store (WinSxS) on ${currentDrive}: - requires admin?") {
            if (-not $DryRun) {
                Write-Host "> " -NoNewline
                Write-Host ([char]0x2713) -ForegroundColor Green -NoNewline
                Write-Host " Running: DISM /Online /Cleanup-Image /StartComponentCleanup"
                try {
                    $dismResult = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup" -Wait -PassThru -NoNewWindow
                    if ($dismResult.ExitCode -eq 0) {
                        $Script:Stats.Success++
                    }
                    else {
                        Write-Host "> " -NoNewline
                        Write-Host "Note:" -ForegroundColor Yellow -NoNewline
                        Write-Host " DISM cleanup may require administrator privileges"
                        $Script:Stats.Skipped++
                    }
                }
                catch {
                    $Script:Stats.Failed++
                    $Script:FailedItems += "WinSxS Cleanup - requires administrator"
                }
            }
            else {
                Write-Host "> [DRY RUN] Would run: DISM /Online /Cleanup-Image /StartComponentCleanup" -ForegroundColor Cyan
                $Script:Stats.Success++
            }
        }

        # 9. Windows Update Logs
        if (Confirm-Action "Clean Windows Update logs on ${currentDrive}:?") {
            Remove-SafePath "$WindowsPath\Logs\CBS" "CBS Logs" "May require admin"
            Remove-SafePath "$WindowsPath\Logs\DISM" "DISM Logs" "May require admin"
            Remove-SafePath "$WindowsPath\Logs\WindowsUpdate" "Windows Update Logs" "May require admin"
            Remove-SafePath "$WindowsPath\SoftwareDistribution\DataStore\Logs" "Update DataStore Logs" "May require admin"
        }

        # 10. Windows Installer info
        if (Confirm-Action "Analyze Windows Installer folder on ${currentDrive}:?") {
            Write-Host "> " -NoNewline
            Write-Host "Note:" -ForegroundColor Yellow -NoNewline
            Write-Host " The Windows Installer folder can be large."
            Write-Host ">   Location: $WindowsPath\Installer - Current size: $(Get-FolderSize "$WindowsPath\Installer")"
            Write-Host ">   Manual cleanup with PatchCleaner is recommended for safety."
            $Script:Stats.Skipped++
        }

        # 11. Hibernation file
        if (Test-Path "${currentDrive}:\hiberfil.sys") {
            $hibSize = Get-FolderSize "${currentDrive}:\hiberfil.sys"
            if (Confirm-Action "Disable hibernation and delete hiberfil.sys on ${currentDrive}: $hibSize?") {
                if (-not $DryRun) {
                    try {
                        $result = Start-Process -FilePath "powercfg.exe" -ArgumentList "/hibernate off" -Wait -PassThru -NoNewWindow
                        if ($result.ExitCode -eq 0) {
                            $Script:Stats.Success++
                            Write-Host "> " -NoNewline
                            Write-Host "Note:" -ForegroundColor Yellow -NoNewline
                            Write-Host " Hibernation disabled. Run 'powercfg /hibernate on' to re-enable."
                        }
                        else {
                            $Script:Stats.Failed++
                            $Script:FailedItems += "Hibernation disable - requires administrator"
                        }
                    }
                    catch {
                        $Script:Stats.Failed++
                    }
                }
                else {
                    Write-Host "> [DRY RUN] Would run: powercfg /hibernate off" -ForegroundColor Cyan
                    $Script:Stats.Success++
                }
            }
        }

        # 12. Font Cache
        if (Confirm-Action "Clean Windows Font Cache on ${currentDrive}:?") {
            Remove-SafePath "$WindowsPath\ServiceProfiles\LocalService\AppData\Local\FontCache" "System Font Cache" "May require admin"
        }

        # 13. Event Logs
        if (Confirm-Action "Clear Windows Event Logs?") {
            if (-not $DryRun) {
                Write-Host "> " -NoNewline
                Write-Host ([char]0x2713) -ForegroundColor Green -NoNewline
                Write-Host " Clearing Windows Event Logs..."
                try {
                    wevtutil el | ForEach-Object {
                        wevtutil cl "$_" 2>$null
                    }
                    $Script:Stats.Success++
                }
                catch {
                    $Script:Stats.Failed++
                }
            }
            else {
                Write-Host "> [DRY RUN] Would clear Windows Event Logs" -ForegroundColor Cyan
                $Script:Stats.Success++
            }
        }

        # 14. Windows Search Index
        if (Confirm-Action "Rebuild Windows Search Index?") {
            if (-not $DryRun) {
                Write-Host "> " -NoNewline
                Write-Host ([char]0x2713) -ForegroundColor Green -NoNewline
                Write-Host " Stopping Windows Search service and clearing index..."
                try {
                    Stop-Service -Name "WSearch" -Force -ErrorAction SilentlyContinue
                    Remove-SafePath "$ProgramDataPath\Microsoft\Search\Data\Applications\Windows" "Windows Search Index"
                    Start-Service -Name "WSearch" -ErrorAction SilentlyContinue
                    Write-Host "> " -NoNewline
                    Write-Host "Note:" -ForegroundColor Yellow -NoNewline
                    Write-Host " Search index will rebuild in background"
                    $Script:Stats.Success++
                }
                catch {
                    $Script:Stats.Failed++
                }
            }
            else {
                Write-Host "> [DRY RUN] Would rebuild Windows Search Index" -ForegroundColor Cyan
                $Script:Stats.Success++
            }
        }

        # 15. Windows Store Cache
        if (Confirm-Action "Clean Windows Store apps cache?") {
            if (-not $DryRun) {
                Write-Host "> " -NoNewline
                Write-Host ([char]0x2713) -ForegroundColor Green -NoNewline
                Write-Host " Running: wsreset.exe (resets Store cache)"
                try {
                    Start-Process -FilePath "wsreset.exe" -Wait -NoNewWindow -ErrorAction SilentlyContinue
                    $Script:Stats.Success++
                }
                catch {
                    $Script:Stats.Skipped++
                }
            }
            else {
                Write-Host "> [DRY RUN] Would run: wsreset.exe" -ForegroundColor Cyan
                $Script:Stats.Success++
            }
        }
    }

    # ==========================================
    # USER PROFILE CLEANUP (for each user on drive)
    # ==========================================

    if ($UserProfiles.Count -gt 0) {
        Write-Host ""
        Write-Host "[User Profile Cleanup on ${currentDrive}:]" -ForegroundColor Cyan
        Write-Host "Found $($UserProfiles.Count) user profile(s): $($UserProfiles.Name -join ', ')" -ForegroundColor Gray
        Write-Host ""

        foreach ($profile in $UserProfiles) {
            $UserProfile = $profile.Path
            $AppData = $profile.AppData
            $LocalAppData = $profile.LocalAppData
            $Temp = $profile.Temp

            Write-Host "--- User: $($profile.Name) ---" -ForegroundColor DarkCyan

            # User Temp Files
            if (Confirm-CommonAction "Clean Temp files for $($profile.Name)?") {
                Remove-SafePath $Temp "User Temp folder ($($profile.Name))"
                Remove-SafePath "$LocalAppData\Temp" "Local Temp ($($profile.Name))"
            }

            # Browser Caches
            if (Confirm-CommonAction "Clean browser caches for $($profile.Name)?") {
                # Chrome
                Remove-SafePath "$LocalAppData\Google\Chrome\User Data\Default\Cache" "Chrome Cache ($($profile.Name))"
                Remove-SafePath "$LocalAppData\Google\Chrome\User Data\Default\Code Cache" "Chrome Code Cache ($($profile.Name))"
                Remove-SafePath "$LocalAppData\Google\Chrome\User Data\Default\GPUCache" "Chrome GPU Cache ($($profile.Name))"

                # Firefox
                $firefoxProfiles = "$AppData\Mozilla\Firefox\Profiles"
                if (Test-Path $firefoxProfiles) {
                    Get-ChildItem -Path $firefoxProfiles -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                        Remove-SafePath "$($_.FullName)\cache2" "Firefox Cache ($($profile.Name))"
                    }
                }

                # Edge
                Remove-SafePath "$LocalAppData\Microsoft\Edge\User Data\Default\Cache" "Edge Cache ($($profile.Name))"
                Remove-SafePath "$LocalAppData\Microsoft\Edge\User Data\Default\Code Cache" "Edge Code Cache ($($profile.Name))"
                Remove-SafePath "$LocalAppData\Microsoft\Edge\User Data\Default\GPUCache" "Edge GPU Cache ($($profile.Name))"

                # Brave
                Remove-SafePath "$LocalAppData\BraveSoftware\Brave-Browser\User Data\Default\Cache" "Brave Cache ($($profile.Name))"
                Remove-SafePath "$LocalAppData\BraveSoftware\Brave-Browser\User Data\Default\Code Cache" "Brave Code Cache ($($profile.Name))"
            }

            # Application Caches
            if (Confirm-CommonAction "Clean application caches for $($profile.Name)?") {
                Remove-SafePath "$AppData\Spotify\Data" "Spotify Cache ($($profile.Name))"
                Remove-SafePath "$AppData\discord\Cache" "Discord Cache ($($profile.Name))"
                Remove-SafePath "$AppData\discord\Code Cache" "Discord Code Cache ($($profile.Name))"
                Remove-SafePath "$AppData\Microsoft\Teams\Cache" "Teams Cache ($($profile.Name))"
                Remove-SafePath "$AppData\Microsoft\Teams\blob_storage" "Teams Blob Storage ($($profile.Name))"
                Remove-SafePath "$AppData\Microsoft\Teams\GPUCache" "Teams GPU Cache ($($profile.Name))"
                Remove-SafePath "$AppData\Slack\Cache" "Slack Cache ($($profile.Name))"
                Remove-SafePath "$LocalAppData\ms-playwright" "Playwright Browsers ($($profile.Name))"
            }

            # GPU Shader Caches
            if (Confirm-CommonAction "Clean GPU shader caches for $($profile.Name)?") {
                Remove-SafePath "$LocalAppData\NVIDIA\DXCache" "NVIDIA DX Cache ($($profile.Name))"
                Remove-SafePath "$LocalAppData\NVIDIA\GLCache" "NVIDIA GL Cache ($($profile.Name))"
                Remove-SafePath "$LocalAppData\NVIDIA Corporation\NV_Cache" "NVIDIA Legacy Cache ($($profile.Name))"
                Remove-SafePath "$LocalAppData\D3DSCache" "Direct3D Cache ($($profile.Name))"
                Remove-SafePath "$LocalAppData\AMD\DxCache" "AMD DX Cache ($($profile.Name))"
                Remove-SafePath "$LocalAppData\AMD\GLCache" "AMD GL Cache ($($profile.Name))"
                Remove-SafePath "$LocalAppData\AMD\VkCache" "AMD Vulkan Cache ($($profile.Name))"
                Remove-SafePath "$LocalAppData\Intel\ShaderCache" "Intel Shader Cache ($($profile.Name))"
            }

            # VS Code
            if (Test-Path "$AppData\Code") {
                if (Confirm-CommonAction "Clean VS Code caches for $($profile.Name)?") {
                    Remove-SafePath "$AppData\Code\Cache" "VS Code Cache ($($profile.Name))"
                    Remove-SafePath "$AppData\Code\CachedData" "VS Code Cached Data ($($profile.Name))"
                    Remove-SafePath "$AppData\Code\CachedExtensions" "VS Code Extensions ($($profile.Name))"
                    Remove-SafePath "$AppData\Code\Code Cache" "VS Code Code Cache ($($profile.Name))"
                    Remove-SafePath "$AppData\Code\GPUCache" "VS Code GPU Cache ($($profile.Name))"
                }
            }

            # Thumbnail Cache
            if (Confirm-CommonAction "Clean thumbnail cache for $($profile.Name)?") {
                $thumbDir = "$LocalAppData\Microsoft\Windows\Explorer"
                if (Test-Path $thumbDir) {
                    $thumbFiles = Get-ChildItem -Path $thumbDir -Filter "thumbcache_*" -ErrorAction SilentlyContinue
                    foreach ($file in $thumbFiles) {
                        Remove-SafePath $file.FullName "Thumbnail Cache ($($profile.Name))"
                    }
                }
            }

            # Windows Error Reporting (User)
            if (Confirm-CommonAction "Clean error reports for $($profile.Name)?") {
                Remove-SafePath "$LocalAppData\Microsoft\Windows\WER" "Error Reports ($($profile.Name))"
                Remove-SafePath "$LocalAppData\CrashDumps" "Crash Dumps ($($profile.Name))"
            }

            # Game Launcher Caches
            if (Test-Path "$LocalAppData\EpicGamesLauncher") {
                if (Confirm-Action "Clean Epic Games cache for $($profile.Name)?") {
                    Remove-SafePath "$LocalAppData\EpicGamesLauncher\Saved\webcache" "Epic Games Cache ($($profile.Name))"
                }
            }

            if (Test-Path "$LocalAppData\GOG.com") {
                if (Confirm-Action "Clean GOG Galaxy cache for $($profile.Name)?") {
                    Remove-SafePath "$LocalAppData\GOG.com\Galaxy\webcache" "GOG Galaxy Cache ($($profile.Name))"
                }
            }

            if (Test-Path "$LocalAppData\Origin") {
                if (Confirm-Action "Clean Origin/EA cache for $($profile.Name)?") {
                    Remove-SafePath "$LocalAppData\Origin\cache" "Origin Cache ($($profile.Name))"
                    Remove-SafePath "$LocalAppData\Electronic Arts\EA Desktop\cache" "EA Desktop Cache ($($profile.Name))"
                }
            }

            # JetBrains
            $jetbrainsPath = "$LocalAppData\JetBrains"
            if (Test-Path $jetbrainsPath) {
                if (Confirm-Action "Clean JetBrains IDE caches for $($profile.Name)?") {
                    Get-ChildItem -Path $jetbrainsPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                        Remove-SafePath "$($_.FullName)\caches" "JetBrains $($_.Name) Caches"
                        Remove-SafePath "$($_.FullName)\index" "JetBrains $($_.Name) Index"
                    }
                }
            }

            # Development Caches
            if (Confirm-Action "Clean development caches for $($profile.Name) (npm, pip, NuGet)?") {
                Remove-SafePath "$AppData\npm-cache" "npm cache ($($profile.Name))"
                Remove-SafePath "$LocalAppData\Yarn\Cache" "Yarn cache ($($profile.Name))"
                Remove-SafePath "$LocalAppData\pip\Cache" "pip cache ($($profile.Name))"
                Remove-SafePath "$UserProfile\.nuget\packages" "NuGet packages ($($profile.Name))"
                Remove-SafePath "$UserProfile\.m2\repository" "Maven cache ($($profile.Name))"
                Remove-SafePath "$UserProfile\.gradle\caches" "Gradle cache ($($profile.Name))"
                Remove-SafePath "$UserProfile\.cargo\registry\cache" "Cargo cache ($($profile.Name))"
                Remove-SafePath "$UserProfile\go\pkg\mod\cache" "Go modules cache ($($profile.Name))"
                Remove-SafePath "$LocalAppData\Composer\cache" "Composer cache ($($profile.Name))"
            }

            # Adobe
            if (Test-Path "$LocalAppData\Adobe") {
                if (Confirm-Action "Clean Adobe cache for $($profile.Name)?") {
                    Remove-SafePath "$LocalAppData\Adobe\Common\Media Cache Files" "Adobe Media Cache ($($profile.Name))"
                    Remove-SafePath "$LocalAppData\Adobe\Common\Media Cache" "Adobe Cache ($($profile.Name))"
                }
            }

            # Office Cache
            if (Test-Path "$LocalAppData\Microsoft\Office") {
                if (Confirm-Action "Clean Microsoft Office cache for $($profile.Name)?") {
                    Remove-SafePath "$LocalAppData\Microsoft\Office\16.0\OfficeFileCache" "Office File Cache ($($profile.Name))"
                    Remove-SafePath "$LocalAppData\Microsoft\Outlook\RoamCache" "Outlook RoamCache ($($profile.Name))"
                }
            }

            # Zoom
            if (Test-Path "$AppData\Zoom") {
                if (Confirm-Action "Clean Zoom cache for $($profile.Name)?") {
                    Remove-SafePath "$AppData\Zoom\data" "Zoom Data ($($profile.Name))"
                    Remove-SafePath "$AppData\Zoom\logs" "Zoom Logs ($($profile.Name))"
                }
            }

            # Recent Files
            if (Confirm-Action "Clean Recent Files for $($profile.Name)?") {
                Remove-SafePath "$AppData\Microsoft\Windows\Recent" "Recent Files ($($profile.Name))"
                Remove-SafePath "$AppData\Microsoft\Windows\Recent\AutomaticDestinations" "Jump Lists ($($profile.Name))"
            }

            # Icon Cache
            if (Confirm-Action "Clean Icon Cache for $($profile.Name)?") {
                $iconFiles = Get-ChildItem -Path "$LocalAppData\Microsoft\Windows\Explorer" -Filter "iconcache_*" -ErrorAction SilentlyContinue
                foreach ($file in $iconFiles) {
                    Remove-SafePath $file.FullName "Icon Cache ($($profile.Name))"
                }
            }

            # Internet Cache
            if (Confirm-Action "Clean IE/Edge Legacy cache for $($profile.Name)?") {
                Remove-SafePath "$LocalAppData\Microsoft\Windows\INetCache" "IE Cache ($($profile.Name))"
            }
        }
    }

    # ==========================================
    # PROGRAM FILES CLEANUP (Steam, etc.)
    # ==========================================

    # Steam (often installed on non-system drives)
    $steamPath = "${currentDrive}:\Program Files (x86)\Steam"
    if (-not (Test-Path $steamPath)) {
        $steamPath = "${currentDrive}:\Steam"
    }
    if (-not (Test-Path $steamPath)) {
        $steamPath = "${currentDrive}:\Games\Steam"
    }

    if (Test-Path $steamPath) {
        if (Confirm-Action "Clean Steam caches on ${currentDrive}:?") {
            Remove-SafePath "$steamPath\depotcache" "Steam Depot Cache (${currentDrive}:)"
            if (Test-Path "$steamPath\steamapps\shadercache") {
                Remove-SafePath "$steamPath\steamapps\shadercache" "Steam Shader Cache (${currentDrive}:)"
            }
            Write-Host "> " -NoNewline
            Write-Host "Tip:" -ForegroundColor Yellow -NoNewline
            Write-Host " Use Steam > Settings > Downloads > Clear Download Cache for complete cleanup"
        }
    }

    # Epic Games (check common locations)
    $epicPath = "${currentDrive}:\Program Files\Epic Games"
    if (-not (Test-Path $epicPath)) {
        $epicPath = "${currentDrive}:\Epic Games"
    }
    if (-not (Test-Path $epicPath)) {
        $epicPath = "${currentDrive}:\Games\Epic Games"
    }

    if (Test-Path $epicPath) {
        if (Confirm-Action "Found Epic Games on ${currentDrive}: - Clean VaultCache?") {
            $vaultCache = "$epicPath\..\Launcher\VaultCache"
            if (Test-Path $vaultCache) {
                Remove-SafePath $vaultCache "Epic Games Vault Cache (${currentDrive}:)"
            }
        }
    }

    # Recycle Bin (per drive)
    if (Confirm-Action "Empty Recycle Bin on ${currentDrive}:?") {
        if (-not $DryRun) {
            Write-Host "> " -NoNewline
            Write-Host ([char]0x2713) -ForegroundColor Green -NoNewline
            Write-Host " Emptying: Recycle Bin on ${currentDrive}:"
            try {
                Clear-RecycleBin -DriveLetter $currentDrive -Force -ErrorAction Stop
                $Script:Stats.Success++
            }
            catch {
                # Try alternative method
                try {
                    $recyclePath = "${currentDrive}:\`$Recycle.Bin"
                    if (Test-Path $recyclePath) {
                        Get-ChildItem -Path $recyclePath -Force -ErrorAction SilentlyContinue | ForEach-Object {
                            Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                    $Script:Stats.Success++
                }
                catch {
                    $Script:Stats.Failed++
                    $Script:FailedItems += "Recycle Bin ${currentDrive}: - $($_.Exception.Message)"
                }
            }
        }
        else {
            Write-Host "> [DRY RUN] Would empty: Recycle Bin on ${currentDrive}:" -ForegroundColor Cyan
            $Script:Stats.Success++
        }
    }
}

#endregion

#region CLI Tool Cleanup (Global - runs once)

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Magenta
Write-Host "  Global CLI Tool Cleanup" -ForegroundColor Magenta
Write-Host ("=" * 60) -ForegroundColor Magenta
Write-Host ""

# Package manager CLI cleanup (runs once regardless of drives)
if ((Test-CommandExists "pnpm") -or (Test-CommandExists "npm") -or (Test-CommandExists "yarn")) {
    if (Confirm-CommonAction "Clean Node package manager caches (npm, pnpm, yarn)?") {
        if (Test-CommandExists "pnpm") {
            if (-not $DryRun) {
                Write-Host "> " -NoNewline
                Write-Host ([char]0x2713) -ForegroundColor Green -NoNewline
                Write-Host " Running: pnpm store prune"
                try { pnpm store prune 2>$null } catch { }
                $Script:Stats.Success++
            }
            else {
                Write-Host "> [DRY RUN] Would run: pnpm store prune" -ForegroundColor Cyan
                $Script:Stats.Success++
            }
        }

        if (Test-CommandExists "npm") {
            if (-not $DryRun) {
                Write-Host "> " -NoNewline
                Write-Host ([char]0x2713) -ForegroundColor Green -NoNewline
                Write-Host " Running: npm cache clean --force"
                try { npm cache clean --force 2>$null } catch { }
                $Script:Stats.Success++
            }
            else {
                Write-Host "> [DRY RUN] Would run: npm cache clean --force" -ForegroundColor Cyan
                $Script:Stats.Success++
            }
        }

        if (Test-CommandExists "yarn") {
            if (-not $DryRun) {
                Write-Host "> " -NoNewline
                Write-Host ([char]0x2713) -ForegroundColor Green -NoNewline
                Write-Host " Running: yarn cache clean"
                try { yarn cache clean 2>$null } catch { }
                $Script:Stats.Success++
            }
            else {
                Write-Host "> [DRY RUN] Would run: yarn cache clean" -ForegroundColor Cyan
                $Script:Stats.Success++
            }
        }
    }
}

if (Test-CommandExists "pip") {
    if (Confirm-CommonAction "Clean Python pip cache?") {
        if (-not $DryRun) {
            Write-Host "> " -NoNewline
            Write-Host ([char]0x2713) -ForegroundColor Green -NoNewline
            Write-Host " Running: pip cache purge"
            try { pip cache purge 2>$null } catch { }
            $Script:Stats.Success++
        }
        else {
            Write-Host "> [DRY RUN] Would run: pip cache purge" -ForegroundColor Cyan
            $Script:Stats.Success++
        }
    }
}

if (Test-CommandExists "dotnet") {
    if (Confirm-Action "Clean NuGet package cache?") {
        if (-not $DryRun) {
            Write-Host "> " -NoNewline
            Write-Host ([char]0x2713) -ForegroundColor Green -NoNewline
            Write-Host " Running: dotnet nuget locals all --clear"
            try { dotnet nuget locals all --clear 2>$null } catch { }
            $Script:Stats.Success++
        }
        else {
            Write-Host "> [DRY RUN] Would run: dotnet nuget locals all --clear" -ForegroundColor Cyan
            $Script:Stats.Success++
        }
    }
}

if (Test-CommandExists "cargo") {
    if (Confirm-Action "Clean Rust cargo cache?") {
        if (-not $DryRun) {
            Write-Host "> " -NoNewline
            Write-Host ([char]0x2713) -ForegroundColor Green -NoNewline
            Write-Host " Running: cargo cache --autoclean (if available)"
            try { cargo cache --autoclean 2>$null } catch { }
            $Script:Stats.Success++
        }
        else {
            Write-Host "> [DRY RUN] Would run: cargo cache --autoclean" -ForegroundColor Cyan
            $Script:Stats.Success++
        }
    }
}

if (Test-CommandExists "go") {
    if (Confirm-Action "Clean Go modules cache?") {
        if (-not $DryRun) {
            Write-Host "> " -NoNewline
            Write-Host ([char]0x2713) -ForegroundColor Green -NoNewline
            Write-Host " Running: go clean -cache"
            try { go clean -cache 2>$null } catch { }
            $Script:Stats.Success++
        }
        else {
            Write-Host "> [DRY RUN] Would run: go clean -cache" -ForegroundColor Cyan
            $Script:Stats.Success++
        }
    }
}

if (Test-CommandExists "composer") {
    if (Confirm-Action "Clean Composer (PHP) cache?") {
        if (-not $DryRun) {
            Write-Host "> " -NoNewline
            Write-Host ([char]0x2713) -ForegroundColor Green -NoNewline
            Write-Host " Running: composer clear-cache"
            try { composer clear-cache 2>$null } catch { }
            $Script:Stats.Success++
        }
        else {
            Write-Host "> [DRY RUN] Would run: composer clear-cache" -ForegroundColor Cyan
            $Script:Stats.Success++
        }
    }
}

if (Test-CommandExists "docker") {
    if (Confirm-Action "Clean Docker build cache?") {
        if (-not $DryRun) {
            Write-Host "> " -NoNewline
            Write-Host ([char]0x2713) -ForegroundColor Green -NoNewline
            Write-Host " Running: docker system prune -f"
            try { docker system prune -f 2>$null } catch { }
            $Script:Stats.Success++
        }
        else {
            Write-Host "> [DRY RUN] Would run: docker system prune -f" -ForegroundColor Cyan
            $Script:Stats.Success++
        }
    }
}

#endregion

#region Summary

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "  CLEANUP SUMMARY" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan

if (-not $DryRun) {
    Write-Host ""
    Write-Host "Final disk usage:" -ForegroundColor Cyan

    $totalFreed = 0
    foreach ($letter in $SelectedDriveLetters) {
        $currentDriveInfo = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='${letter}:'"
        if ($currentDriveInfo) {
            $freeAfter = $currentDriveInfo.FreeSpace
            $freeBefore = $TotalFreeBefore[$letter]
            $freed = $freeAfter - $freeBefore
            $totalFreed += $freed

            $freeGB = [math]::Round($freeAfter / 1GB, 2)
            $usedGB = [math]::Round(($currentDriveInfo.Size - $freeAfter) / 1GB, 2)
            $percentUsed = [math]::Round((($currentDriveInfo.Size - $freeAfter) / $currentDriveInfo.Size) * 100, 1)
            $freedDisplay = Format-ByteSize $freed

            $usedColor = if ($percentUsed -gt 90) { "Red" } elseif ($percentUsed -gt 70) { "Yellow" } else { "White" }

            Write-Host "  ${letter}: " -NoNewline
            Write-Host "Used: ${usedGB}GB / Free: ${freeGB}GB " -NoNewline
            Write-Host "($percentUsed% full)" -ForegroundColor $usedColor -NoNewline
            if ($freed -gt 0) {
                Write-Host " - Freed: " -NoNewline
                Write-Host $freedDisplay -ForegroundColor Green
            }
            else {
                Write-Host ""
            }
        }
    }

    Write-Host ""
    $totalFreedDisplay = Format-ByteSize $totalFreed
    Write-Host "Total space freed: " -NoNewline -ForegroundColor Cyan
    Write-Host "~$totalFreedDisplay" -ForegroundColor Green
    Write-Host ""

    Write-Host "Statistics:" -ForegroundColor Cyan
    Write-Host "> " -NoNewline
    Write-Host ([char]0x2713) -ForegroundColor Green -NoNewline
    Write-Host " Successfully cleaned: $($Script:Stats.Success) items"

    if ($Script:Stats.Empty -gt 0) {
        Write-Host "> " -NoNewline
        Write-Host ([char]0x2298) -ForegroundColor Yellow -NoNewline
        Write-Host " Skipped (empty): $($Script:Stats.Empty) items"
    }

    if ($Script:Stats.Skipped -gt 0) {
        Write-Host "> " -NoNewline
        Write-Host ([char]0x2298) -ForegroundColor Yellow -NoNewline
        Write-Host " Skipped (not found): $($Script:Stats.Skipped) items"
    }

    if ($Script:Stats.Failed -gt 0) {
        Write-Host "> " -NoNewline
        Write-Host ([char]0x2717) -ForegroundColor Red -NoNewline
        Write-Host " Failed: $($Script:Stats.Failed) items"
        Write-Host ""
        Write-Host "Failed items (may need manual attention):" -ForegroundColor Yellow
        foreach ($item in $Script:FailedItems) {
            Write-Host "  - $item"
        }
    }
}
else {
    Write-Host ""
    Write-Host "Dry run complete. No files were deleted." -ForegroundColor Yellow
    Write-Host "Run without -DryRun to actually clean up."
    Write-Host ""
    Write-Host "Statistics:" -ForegroundColor Cyan
    Write-Host "> Would clean: $($Script:Stats.Success) items" -ForegroundColor Cyan

    if ($Script:Stats.Empty -gt 0) {
        Write-Host "> Would skip (empty): $($Script:Stats.Empty) items" -ForegroundColor Yellow
    }

    if ($Script:Stats.Skipped -gt 0) {
        Write-Host "> Would skip (not found): $($Script:Stats.Skipped) items" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "  Cleanup complete!" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Cyan

#endregion
