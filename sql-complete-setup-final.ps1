# Complete SQL Server Setup Script - Final Version (No Templates)
param(
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory=$true)]
    [string]$StorageAccountKey,

    [Parameter(Mandatory=$true)]
    [string]$ShareName,

    [Parameter(Mandatory=$true)]
    [string]$DriveLetter,

    [Parameter(Mandatory=$true)]
    [string]$SqlPassword,

    [Parameter(Mandatory=$true)]
    [string]$EnableDbRestore
)

# Enhanced logging function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Output $logMessage

    try {
        $logFile = "C:\sql-complete-setup.log"
        Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
    } catch {
        # Ignore logging errors
    }
}

Write-Log "=== Complete SQL Server Setup Starting ==="
Write-Log "Storage Account: $StorageAccountName"
Write-Log "Share Name: $ShareName"
Write-Log "Drive Letter: $DriveLetter"
Write-Log "Enable DB Restore: $EnableDbRestore"
Write-Log "Storage Key Length: $($StorageAccountKey.Length) characters"

try {
    # Step 1: Create SQLBackups directory on SQL Server
    Write-Log "=== STEP 1: Creating SQLBackups directory ==="
    $sqlBackupsPath = "F:\SQLBackups"
    if (-not (Test-Path $sqlBackupsPath)) {
        New-Item -Path $sqlBackupsPath -ItemType Directory -Force | Out-Null
        Write-Log "SQLBackups directory created: $sqlBackupsPath"
    } else {
        Write-Log "SQLBackups directory already exists: $sqlBackupsPath"
    }

    # Step 2: Install SSMS
    Write-Log "=== STEP 2: Installing SSMS ==="
    $ssmsPath = "C:\ssms.exe"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Write-Log "Downloading SSMS installer..."
    Invoke-WebRequest -Uri "https://aka.ms/ssmsfullsetup" -OutFile $ssmsPath -UseBasicParsing -TimeoutSec 300
    Write-Log "SSMS installer downloaded"

    Write-Log "Installing SSMS (this may take several minutes)..."
    $installProcess = Start-Process $ssmsPath -ArgumentList '/Quiet /Install' -Wait -PassThru

    if ($installProcess.ExitCode -eq 0) {
        Write-Log "SSMS installation completed successfully"
    } else {
        Write-Log "SSMS installation completed with exit code: $($installProcess.ExitCode)" "WARNING"
    }

    if (Test-Path $ssmsPath) {
        Remove-Item $ssmsPath -Force -ErrorAction SilentlyContinue
    }

    # Step 3: Mount Azure File Share
    Write-Log "=== STEP 3: Mounting Azure File Share ==="
    $fqdn = "$StorageAccountName.file.core.windows.net"
    $uncPath = "\\$fqdn\$ShareName"
    $drivePath = "$DriveLetter" + ":"

    Write-Log "Mounting Azure File Share:"
    Write-Log "  FQDN: $fqdn"
    Write-Log "  UNC Path: $uncPath"
    Write-Log "  Drive Path: $drivePath"

    # Test connectivity
    $connectTest = Test-NetConnection -ComputerName $fqdn -Port 445 -WarningAction SilentlyContinue
    if ($connectTest.TcpTestSucceeded) {
        Write-Log "Port 445 connectivity successful"
    } else {
        Write-Log "Port 445 connectivity failed" "ERROR"
        throw "Cannot connect to storage account on port 445"
    }

    # Clean up existing mappings
    try {
        Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue | Remove-PSDrive -Force -ErrorAction SilentlyContinue
        cmd.exe /C "net use $drivePath /delete /y" 2>&1 | Out-Null
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

    # Step 4: Wait for backup files from BETA01
    Write-Log "=== STEP 4: Waiting for backup files from BETA01 ==="
    $sourcePath = "$drivePath\SQLBACKUPS"
    $maxWaitTime = 1800  # 30 minutes
    $checkInterval = 60  # Check every minute
    $waitTime = 0
    $filesFound = $false
    $backupFiles = @()

    # Check for completion marker (optional)
    $beta01CompletionMarker = "$sourcePath\BETA01_BACKUP_COMPLETE.txt"
    Write-Log "Looking for completion marker: $beta01CompletionMarker"
    Write-Log "Looking for backup files in: $sourcePath"

    while ($waitTime -lt $maxWaitTime) {
        if (Test-Path $sourcePath) {
            Write-Log "SQLBACKUPS directory exists, checking contents..."

            $allSourceFiles = Get-ChildItem -Path $sourcePath -ErrorAction SilentlyContinue
            Write-Log "Files found in source directory: $($allSourceFiles.Count)"

            $backupFiles = Get-ChildItem -Path $sourcePath -Filter "*.bak" -File -ErrorAction SilentlyContinue
            if ($backupFiles.Count -gt 0) {
                Write-Log "Found $($backupFiles.Count) backup files after $waitTime seconds"

                # Proceed if files exist, regardless of completion marker
                # Wait at least 5 minutes to ensure BETA01 has finished copying
                if ($waitTime -gt 300) {
                    Write-Log "Backup files found and minimum wait time elapsed - proceeding with copy operation"
                    $filesFound = $true
                    break
                } else {
                    Write-Log "Backup files found but waiting minimum 5 minutes for BETA01 to complete"
                }
            } else {
                Write-Log "No .bak files found yet (found $($allSourceFiles.Count) total files)"
            }
        } else {
            Write-Log "SQLBACKUPS directory does not exist yet: $sourcePath"
        }

        Write-Log "Waiting for backup files... ($waitTime seconds elapsed, max: $maxWaitTime)"
        Start-Sleep -Seconds $checkInterval
        $waitTime += $checkInterval
    }

    if (-not $filesFound) {
        Write-Log "No backup files found after $maxWaitTime seconds" "WARNING"
        Write-Log "Azure File Share is mounted and ready for future use"
        Write-Log "=== SQL Server Setup Completed (No backup files available) ==="
        exit 0
    }

    # Step 5: Copy backup files to local storage
    Write-Log "=== STEP 5: Copying backup files to local storage ==="
    $destinationPath = "F:\SQLBackups"

    if (-not (Test-Path $destinationPath)) {
        New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
        Write-Log "Created local backup directory: $destinationPath"
    } else {
        Write-Log "Local backup directory already exists: $destinationPath"
    }

    # Verify destination is writable
    try {
        $testFile = Join-Path $destinationPath "test.tmp"
        "test" | Out-File -FilePath $testFile -Force
        if (Test-Path $testFile) {
            Remove-Item $testFile -Force
            Write-Log "Destination directory is writable"
        }
    } catch {
        Write-Log "Destination directory is not writable: $($_.Exception.Message)" "ERROR"
        throw "Cannot write to destination directory"
    }

    # Log source files before copying
    Write-Log "Source files found:"
    foreach ($file in $backupFiles) {
        Write-Log "  Source: $($file.Name) - Size: $([math]::Round($file.Length/1MB, 2)) MB"
    }

    $successCount = 0
    foreach ($file in $backupFiles) {
        try {
            $destinationFile = Join-Path $destinationPath $file.Name
            Write-Log "Copying: $($file.Name)"
            Write-Log "  From: $($file.FullName)"
            Write-Log "  To: $destinationFile"

            if (-not (Test-Path $file.FullName)) {
                Write-Log "  SOURCE FILE NOT ACCESSIBLE" "ERROR"
                continue
            }

            Copy-Item -Path $file.FullName -Destination $destinationFile -Force -Verbose
            Start-Sleep -Seconds 2

            if (Test-Path $destinationFile) {
                $copiedFile = Get-Item $destinationFile
                if ($copiedFile.Length -eq $file.Length) {
                    Write-Log "  SUCCESS - File copied and verified"
                    $successCount++
                } else {
                    Write-Log "  SIZE MISMATCH - Original: $($file.Length), Copied: $($copiedFile.Length)" "ERROR"
                }
            } else {
                Write-Log "  COPY FAILED - Destination file does not exist" "ERROR"
            }
        } catch {
            Write-Log "  COPY ERROR: $($_.Exception.Message)" "ERROR"
        }
    }

    Write-Log "Copy operation completed: $successCount of $($backupFiles.Count) files copied successfully"

    # Verify local files exist
    Write-Log "Verifying local backup files exist:"
    $localBackupFiles = Get-ChildItem -Path $destinationPath -Filter "*.bak" -ErrorAction SilentlyContinue
    if ($localBackupFiles.Count -gt 0) {
        Write-Log "Found $($localBackupFiles.Count) backup files in local directory:"
        foreach ($localFile in $localBackupFiles) {
            Write-Log "  $($localFile.Name) ($([math]::Round($localFile.Length/1MB, 2)) MB)"
        }
    } else {
        Write-Log "No backup files found in local directory after copy operation!" "ERROR"
        throw "Copy operation failed - no backup files in destination directory"
    }

    # Step 6: Database Restore (if enabled)
    if ($EnableDbRestore -eq "true" -or $EnableDbRestore -eq "True") {
        Write-Log "=== STEP 6: Restoring Databases from Local Storage ==="

        # Wait for SQL Server to be ready
        Write-Log "Waiting for SQL Server to be ready..."
        Start-Sleep -Seconds 60

        # Test SQL connectivity
        $sqlReady = $false
        for ($i = 1; $i -le 5; $i++) {
            try {
                $testResult = sqlcmd -S localhost -U Yoda -P "$SqlPassword" -Q "SELECT @@VERSION" -b -t 10
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "SQL Server is ready"
                    $sqlReady = $true
                    break
                }
            } catch {
                # Continue trying
            }
            Write-Log "SQL Server not ready, attempt $i/5..."
            Start-Sleep -Seconds 30
        }

        if (-not $sqlReady) {
            Write-Log "SQL Server did not become ready" "ERROR"
            throw "SQL Server connectivity failed"
        }

        # Restore databases
        $databases = @(
            @{Name="EWN"; File="EWN_Current.bak"},
            @{Name="DataWarehouse"; File="DataWarehouse_Current.bak"},
            @{Name="Quartz"; File="Quartz_Current.bak"},
            @{Name="Rustici"; File="Rustici_Current.bak"},
            @{Name="TestDB"; File="TestDB_Current.bak"}
        )

        $restoredCount = 0
        foreach ($db in $databases) {
            $backupFile = "F:\SQLBackups\$($db.File)"

            if (Test-Path $backupFile) {
                Write-Log "Restoring database: $($db.Name) from local file: $backupFile"

                # Get logical file names from backup first
                $fileListCmd = "RESTORE FILELISTONLY FROM DISK = N'$backupFile'"
                try {
                    $fileList = sqlcmd -S localhost -U Yoda -P "$SqlPassword" -Q "$fileListCmd" -b -t 30
                    Write-Log "File list for $($db.Name): $fileList"
                } catch {
                    Write-Log "Could not get file list for $($db.Name)" "WARNING"
                }

                # Create target directory if needed
                $targetDir = "F:\Databases\UserDBs"
                if (-not (Test-Path $targetDir)) {
                    New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
                    Write-Log "Created target directory: $targetDir"
                }

                $restoreCmd = @"
RESTORE DATABASE [$($db.Name)]
FROM DISK = N'$backupFile'
WITH REPLACE, STATS = 10,
MOVE '$($db.Name)' TO 'F:\Databases\UserDBs\$($db.Name).mdf',
MOVE '$($db.Name)_Log' TO 'F:\Databases\UserDBs\$($db.Name)_Log.ldf'
"@

                $restoreResult = sqlcmd -S localhost -U Yoda -P "$SqlPassword" -Q "$restoreCmd" -b -t 1800

                if ($LASTEXITCODE -eq 0) {
                    Write-Log "  $($db.Name) restored successfully"
                    $restoredCount++
                } else {
                    Write-Log "  $($db.Name) restore failed (Exit Code: $LASTEXITCODE)" "ERROR"
                }
            } else {
                Write-Log "  Backup file not found: $backupFile" "WARNING"
            }
        }

        # Verify databases
        Write-Log "Verifying restored databases..."
        $verifyCmd = "SELECT name, state_desc FROM sys.databases WHERE name IN ('EWN', 'DataWarehouse', 'Quartz', 'Rustici', 'TestDB')"
        $dbStatus = sqlcmd -S localhost -U Yoda -P "$SqlPassword" -Q "$verifyCmd" -b -t 30

        Write-Log "Database Status:"
        $dbStatus | ForEach-Object { if ($_ -and $_ -notmatch "rows affected") { Write-Log "  $_" } }

        Write-Log "Successfully restored $restoredCount databases"
    } else {
        Write-Log "Database restore is disabled - skipping restore step"
    }

    Write-Log "=== Complete SQL Server Setup Finished Successfully ==="

} catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" "ERROR"
    Write-Log "Setup failed - check log for details"
    exit 1
}