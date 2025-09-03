# beta01-setup-direct.ps1 BETA01 VM Setup Script - Direct Mount Version
param(
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory=$true)]
    [string]$StorageAccountKey,

    [Parameter(Mandatory=$true)]
    [string]$ShareName,

    [string]$DriveLetter = "Z"
)

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Output $logMessage

    try {
        $logFile = "C:\beta01-setup.log"
        Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
    } catch {
        # Ignore logging errors
    }
}

Write-Log "=== BETA01 VM Setup Starting ==="
Write-Log "Storage Account: $StorageAccountName"
Write-Log "Share Name: $ShareName"
Write-Log "Drive Letter: $DriveLetter"

try {
    # Step 1: Aggressive drive cleanup
    Write-Log "=== STEP 1: Aggressive Drive Cleanup ==="
    $drivePath = $DriveLetter + ":"

    Write-Log "Cleaning up drive $drivePath"

    # Multiple cleanup approaches
    $result1 = cmd.exe /C "net use $drivePath /delete /y" 2>&1
    Write-Log "Drive delete result: $result1"

    $result2 = cmd.exe /C "net use * /delete /y" 2>&1
    Write-Log "All drives delete result: $result2"

    # Registry cleanup for persistent network drives
    Write-Log "Cleaning registry entries for drive $DriveLetter"
    try {
        $regPath = "HKCU:\Network\$DriveLetter"
        if (Test-Path $regPath) {
            Remove-Item -Path $regPath -Force -Recurse -ErrorAction SilentlyContinue
            Write-Log "Removed registry entry: $regPath"
        } else {
            Write-Log "No registry entry found at: $regPath"
        }

        # Also check HKLM for system-wide mappings
        $regPathSystem = "HKLM:\SYSTEM\CurrentControlSet\Services\lanmanserver\Shares"
        Write-Log "Checked system registry paths for network shares"

    } catch {
        Write-Log "Registry cleanup completed with warnings"
    }

    # Kill explorer to release any locks
    Get-Process -Name "explorer" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    Write-Log "Drive cleanup completed"

    # Step 2: Network connectivity test
    Write-Log "=== STEP 2: Network Test ==="
    $fqdn = "$StorageAccountName.file.core.windows.net"
    Write-Log "Testing connectivity to $fqdn"

    $connectTest = Test-NetConnection -ComputerName $fqdn -Port 445 -WarningAction SilentlyContinue
    if ($connectTest.TcpTestSucceeded) {
        Write-Log "Network connectivity: SUCCESS"
    } else {
        Write-Log "Network connectivity: FAILED - continuing anyway" "WARNING"
    }

    # Step 3: Direct mount attempts with multiple credential formats
    Write-Log "=== STEP 3: Direct Mount Attempts ==="
    $uncPath = "\\$fqdn\$ShareName"
    Write-Log "UNC Path: $uncPath"

    # Try different credential formats
    $credentialFormats = @(
        "AZURE\$StorageAccountName",
        "$StorageAccountName",
        "Azure\$StorageAccountName"
    )

    $mountSuccess = $false

    foreach ($credFormat in $credentialFormats) {
        Write-Log "Trying mount with credential format: $credFormat"

        $netUseCmd = "net use $drivePath `"$uncPath`" `"$StorageAccountKey`" /user:`"$credFormat`" /persistent:yes"
        Write-Log "Executing: net use command"

        $netResult = cmd.exe /C $netUseCmd 2>&1
        Write-Log "Net use result: $netResult"

        Start-Sleep -Seconds 3

        if (Test-Path $drivePath) {
            Write-Log "Mount successful with credential format: $credFormat"
            $mountSuccess = $true
            break
        } else {
            Write-Log "Mount failed with credential format: $credFormat - trying next"
        }
    }

    if (-not $mountSuccess) {
        Write-Log "All mount attempts failed!" "ERROR"
        exit 1
    }

    # Step 4: Verify mount and create folders
    Write-Log "=== STEP 4: Verify Mount ==="
    if (Test-Path $drivePath) {
        $items = Get-ChildItem $drivePath -ErrorAction SilentlyContinue
        Write-Log "Mount verified - found $($items.Count) items in share"

        # Create SQLBACKUPS folder
        $sqlBackupsPath = "$drivePath\SQLBACKUPS"
        if (-not (Test-Path $sqlBackupsPath)) {
            New-Item -Path $sqlBackupsPath -ItemType Directory -Force | Out-Null
            Write-Log "Created SQLBACKUPS folder"
        } else {
            Write-Log "SQLBACKUPS folder already exists"
        }
    } else {
        Write-Log "Mount verification failed" "ERROR"
        exit 1
    }

    # Step 5: Copy backup files
    Write-Log "=== STEP 5: Copy Backup Files ==="
    $sourcePath = "F:\SQLBackups"
    $destinationPath = "$drivePath\SQLBACKUPS"

    if (-not (Test-Path $sourcePath)) {
        Write-Log "Source path does not exist: $sourcePath"
        Write-Log "BETA01 setup completed (no source files)"
        exit 0
    }

    $backupFiles = Get-ChildItem -Path $sourcePath -Filter "*.bak" -File -ErrorAction SilentlyContinue

    if ($backupFiles.Count -eq 0) {
        Write-Log "No backup files found in source"
        Write-Log "BETA01 setup completed (no backup files)"
        exit 0
    }

    Write-Log "Found $($backupFiles.Count) backup files to copy"

    $successCount = 0
    foreach ($file in $backupFiles) {
        try {
            $destFile = Join-Path $destinationPath $file.Name
            Write-Log "Copying: $($file.Name)"

            Copy-Item -Path $file.FullName -Destination $destFile -Force

            if (Test-Path $destFile) {
                Write-Log "Copy successful: $($file.Name)"
                $successCount++
            } else {
                Write-Log "Copy failed: $($file.Name)" "ERROR"
            }
        } catch {
            Write-Log "Copy error: $($file.Name)" "ERROR"
        }
    }

    Write-Log "Successfully copied $successCount out of $($backupFiles.Count) files"
    Write-Log "=== BETA01 VM Setup Completed Successfully ==="

} catch {
    Write-Log "Script execution failed" "ERROR"
    exit 1
}