# BETA01 Setup Script - Final Version (No Templates)
param(
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory=$true)]
    [string]$StorageAccountKey,

    [Parameter(Mandatory=$true)]
    [string]$ShareName,

    [Parameter(Mandatory=$true)]
    [string]$DriveLetter
)

# Enhanced logging function
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

Write-Log "=== BETA01 Setup Starting ==="
Write-Log "Storage Account: $StorageAccountName"
Write-Log "Share Name: $ShareName"
Write-Log "Drive Letter: $DriveLetter"

try {
    # Step 1: Check for backup files on BETA01
    Write-Log "=== STEP 1: Checking for backup files on BETA01 ==="
    $localBackupPath = "F:\SQLBackups"

    if (-not (Test-Path $localBackupPath)) {
        Write-Log "Local backup directory does not exist: $localBackupPath" "ERROR"
        Write-Log "=== BETA01 Setup Completed (No backups to copy) ==="
        exit 0
    }

    $localBackupFiles = Get-ChildItem -Path $localBackupPath -Filter "*.bak" -File -ErrorAction SilentlyContinue

    if ($localBackupFiles.Count -eq 0) {
        Write-Log "No .bak files found in: $localBackupPath" "WARNING"
        Write-Log "=== BETA01 Setup Completed (No .bak files to copy) ==="
        exit 0
    }

    Write-Log "Found $($localBackupFiles.Count) backup files on BETA01:"
    foreach ($file in $localBackupFiles) {
        Write-Log "  Local backup: $($file.Name) ($([math]::Round($file.Length/1MB, 2)) MB)"
    }

    # Step 2: Test network connectivity
    Write-Log "=== STEP 2: Testing network connectivity ==="
    $fqdn = "$StorageAccountName.file.core.windows.net"

    Write-Log "Testing connectivity to $fqdn on port 445..."
    $connectTest = Test-NetConnection -ComputerName $fqdn -Port 445 -WarningAction SilentlyContinue

    if ($connectTest.TcpTestSucceeded) {
        Write-Log "Port 445 connectivity successful"
    } else {
        Write-Log "Port 445 connectivity failed" "ERROR"
        throw "Cannot connect to storage account on port 445"
    }

    # Step 3: Mount Azure File Share
    Write-Log "=== STEP 3: Mounting Azure File Share ==="
    $uncPath = "\\$fqdn\$ShareName"
    $drivePath = "$DriveLetter" + ":"

    Write-Log "Mounting Azure File Share:"
    Write-Log "  UNC Path: $uncPath"
    Write-Log "  Drive Path: $drivePath"

    # Clean up existing mappings
    try {
        Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue | Remove-PSDrive -Force -ErrorAction SilentlyContinue
        cmd.exe /C "net use $drivePath /delete /y" 2>&1 | Out-Null
        Write-Log "Cleaned up existing drive mappings"
    } catch {
        # Ignore cleanup errors
    }

    Start-Sleep -Seconds 3

    # Mount using net use
    Write-Log "Mounting drive using net use..."
    $netUseCmd = "net use $drivePath `"$uncPath`" `"$StorageAccountKey`" /user:`"AZURE\$StorageAccountName`" /persistent:yes"
    $netResult = cmd.exe /C $netUseCmd 2>&1
    Write-Log "Net use result: $netResult"

    Start-Sleep -Seconds 5

    if (Test-Path $drivePath) {
        $items = Get-ChildItem $drivePath -ErrorAction SilentlyContinue
        Write-Log "Azure File Share mounted successfully to $drivePath"
        Write-Log "Items in share: $($items.Count)"
    } else {
        throw "Drive mount failed - $drivePath not accessible"
    }

    # Step 4: Prepare SQLBACKUPS directory
    Write-Log "=== STEP 4: Preparing SQLBACKUPS directory ==="
    $shareBackupPath = "$drivePath\SQLBACKUPS"

    if (-not (Test-Path $shareBackupPath)) {
        Write-Log "Creating SQLBACKUPS directory in Azure File Share..."
        New-Item -Path $shareBackupPath -ItemType Directory -Force | Out-Null
        Write-Log "SQLBACKUPS directory created: $shareBackupPath"
    } else {
        Write-Log "SQLBACKUPS directory already exists: $shareBackupPath"
    }

    # Check existing files
    $existingFiles = Get-ChildItem -Path $shareBackupPath -ErrorAction SilentlyContinue
    Write-Log "Existing files in SQLBACKUPS: $($existingFiles.Count)"

    # Step 5: Copy backup files
    Write-Log "=== STEP 5: Copying backup files to Azure File Share ==="

    $successCount = 0
    $errorCount = 0
    $skippedCount = 0

    foreach ($file in $localBackupFiles) {
        try {
            $destinationFile = Join-Path $shareBackupPath $file.Name
            Write-Log "Processing: $($file.Name) ($([math]::Round($file.Length/1MB, 2)) MB)"

            # Check if file already exists
            if (Test-Path $destinationFile) {
                $destFile = Get-Item $destinationFile
                if ($destFile.Length -eq $file.Length) {
                    Write-Log "  SKIPPED - File already exists with same size"
                    $skippedCount++
                    continue
                }
            }

            # Copy the file
            Copy-Item -Path $file.FullName -Destination $destinationFile -Force
            Start-Sleep -Seconds 2

            # Verify copy
            if (Test-Path $destinationFile) {
                $copiedFile = Get-Item $destinationFile
                if ($copiedFile.Length -eq $file.Length) {
                    Write-Log "  SUCCESS - File copied and verified"
                    $successCount++
                } else {
                    Write-Log "  SIZE MISMATCH" "ERROR"
                    $errorCount++
                }
            } else {
                Write-Log "  COPY FAILED" "ERROR"
                $errorCount++
            }

        } catch {
            Write-Log "  COPY ERROR: $($_.Exception.Message)" "ERROR"
            $errorCount++
        }
    }

    # Step 6: Create completion marker
    Write-Log "=== STEP 6: Creating completion marker ==="
    try {
        $completionMarker = "$shareBackupPath\BETA01_BACKUP_COMPLETE.txt"
        $completionMessage = @"
BETA01 backup copy completed at $(Get-Date)
Files successfully copied: $successCount
Files skipped (already existed): $skippedCount
Files with errors: $errorCount
Total backup files processed: $($localBackupFiles.Count)

Backup files available for SQL Server restore:
"@

        # Add list of final files
        $finalFiles = Get-ChildItem -Path $shareBackupPath -Filter "*.bak" -File -ErrorAction SilentlyContinue
        foreach ($finalFile in $finalFiles) {
            $completionMessage += "`n- $($finalFile.Name) ($([math]::Round($finalFile.Length/1MB, 2)) MB)"
        }

        $completionMessage | Out-File -FilePath $completionMarker -Force
        Write-Log "Created completion marker: $completionMarker"
    } catch {
        Write-Log "Could not create completion marker: $($_.Exception.Message)" "WARNING"
    }

    # Final summary
    Write-Log "=== STEP 7: Final Summary ==="
    Write-Log "Files successfully copied: $successCount"
    Write-Log "Files skipped: $skippedCount"
    Write-Log "Files with errors: $errorCount"
    Write-Log "Total files processed: $($localBackupFiles.Count)"

    if ($errorCount -eq 0) {
        Write-Log "=== BETA01 Setup Completed Successfully ==="
    } else {
        Write-Log "=== BETA01 Setup Completed with $errorCount errors ===" "WARNING"
    }

} catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" "ERROR"
    Write-Log "BETA01 setup failed"
    exit 1
}