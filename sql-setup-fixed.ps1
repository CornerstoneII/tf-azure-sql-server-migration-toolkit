# SQL Server VM Setup Script - Fixed Version
param(
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory=$true)]
    [string]$StorageAccountKey,

    [Parameter(Mandatory=$true)]
    [string]$ShareName,

    [string]$DriveLetter = "Y",

    [Parameter(Mandatory=$true)]
    [string]$SqlPassword
)

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Output $logMessage

    try {
        $logFile = "C:\sql-setup.log"
        Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
    } catch {
        # Ignore logging errors
    }
}

Write-Log "=== SQL Server VM Setup Starting ==="
Write-Log "Storage Account: $StorageAccountName"
Write-Log "Share Name: $ShareName"
Write-Log "Drive Letter: $DriveLetter"
Write-Log "Storage Key Length: $($StorageAccountKey.Length) characters"
Write-Log "SQL Password Length: $($SqlPassword.Length) characters"

try {
    # Step 1: Create SQLBackups directory
    Write-Log "=== STEP 1: Creating SQLBackups directory ==="
    $sqlBackupsPath = "F:\SQLBackups"

    if (-not (Test-Path $sqlBackupsPath)) {
        Write-Log "Creating SQLBackups directory: $sqlBackupsPath"
        New-Item -Path $sqlBackupsPath -ItemType Directory -Force | Out-Null
        Write-Log "SQLBackups directory created successfully"
    } else {
        Write-Log "SQLBackups directory already exists: $sqlBackupsPath"
    }

    # Step 2: Install SSMS
    Write-Log "=== STEP 2: Installing SSMS ==="
    Write-Log "Downloading SSMS installer..."
    $ssmsPath = "C:\ssms.exe"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri "https://aka.ms/ssmsfullsetup" -OutFile $ssmsPath -UseBasicParsing -TimeoutSec 300
    Write-Log "SSMS installer downloaded successfully"

    Write-Log "Starting SSMS installation..."
    $installProcess = Start-Process $ssmsPath -ArgumentList '/Quiet /Install' -Wait -PassThru

    if ($installProcess.ExitCode -eq 0) {
        Write-Log "SSMS installation completed successfully"
    } else {
        Write-Log "SSMS installation completed with exit code: $($installProcess.ExitCode)" "WARNING"
    }

    if (Test-Path $ssmsPath) {
        Remove-Item $ssmsPath -Force -ErrorAction SilentlyContinue
    }

    # Step 3: Network and Storage Validation
    Write-Log "=== STEP 3: Network and Storage Validation ==="
    $fqdn = "$StorageAccountName.file.core.windows.net"
    $uncPath = "\\$fqdn\$ShareName"

    Write-Log "Testing network connectivity to $fqdn on port 445..."
    $connectTest = Test-NetConnection -ComputerName $fqdn -Port 445 -WarningAction SilentlyContinue

    if ($connectTest.TcpTestSucceeded) {
        Write-Log "Port 445 connectivity: SUCCESS"
    } else {
        Write-Log "Port 445 connectivity: FAILED" "WARNING"
    }

    # Test storage account authentication
    Write-Log "Testing storage account authentication..."
    $secureKey = ConvertTo-SecureString -String $StorageAccountKey -AsPlainText -Force
    $credentialFormats = @("AZURE\$StorageAccountName", "$StorageAccountName")
    $authSuccess = $false
    $workingCredFormat = $null

    foreach ($credFormat in $credentialFormats) {
        try {
            Write-Log "Testing authentication with credential format: $credFormat"
            $testCred = New-Object System.Management.Automation.PSCredential($credFormat, $secureKey)
            $testDrive = New-PSDrive -Name "TEMP_AUTH_TEST" -PSProvider FileSystem -Root $uncPath -Credential $testCred -ErrorAction Stop
            Remove-PSDrive -Name "TEMP_AUTH_TEST" -Force

            Write-Log "Authentication successful with: $credFormat"
            $authSuccess = $true
            $workingCredFormat = $credFormat
            break
        } catch {
            Write-Log "Authentication failed with $credFormat : $($_.Exception.Message)" "WARNING"
        }
    }

    if (-not $authSuccess) {
        Write-Log "All authentication attempts failed!" "ERROR"
        Write-Log "This usually indicates incorrect storage key or network issues" "ERROR"
        exit 1
    }

    # Step 4: Mount Azure File Share
    Write-Log "=== STEP 4: Mounting Azure File Share ==="
    $drivePath = "$DriveLetter" + ":"

    Write-Log "Attempting to mount Azure File Share..."
    Write-Log "UNC Path: $uncPath"
    Write-Log "Drive Path: $drivePath"

    # Clean up existing mappings
    try {
        Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue | Remove-PSDrive -Force -ErrorAction SilentlyContinue
        Write-Log "Cleaned up existing PowerShell drive"
    } catch {
        Write-Log "No PowerShell drive to clean up"
    }

    try {
        $netUseOutput = cmd.exe /C "net use $drivePath /delete /y" 2>&1
        Write-Log "Net use delete output: $netUseOutput"
        Start-Sleep -Seconds 2
    } catch {
        Write-Log "No existing net use mapping to clean up"
    }

    # Mount using the working credential format
    $credential = New-Object System.Management.Automation.PSCredential($workingCredFormat, $secureKey)

    try {
        New-PSDrive -Name $DriveLetter -PSProvider FileSystem -Root $uncPath -Credential $credential -Persist -ErrorAction Stop
        Start-Sleep -Seconds 5

        if (Test-Path $drivePath) {
            $items = Get-ChildItem $drivePath -ErrorAction SilentlyContinue
            Write-Log "Azure File Share successfully mounted to $DriveLetter drive"
            Write-Log "Items in root of share: $($items.Count)"

            $sqlBackupsSharePath = Join-Path $drivePath "SQLBACKUPS"
            if (Test-Path $sqlBackupsSharePath) {
                Write-Log "SQLBACKUPS folder found in share"
            } else {
                Write-Log "Creating SQLBACKUPS folder in share..."
                New-Item -Path $sqlBackupsSharePath -ItemType Directory -Force | Out-Null
                Write-Log "SQLBACKUPS folder created in share"
            }
        } else {
            Write-Log "Drive mounted but not accessible" "ERROR"
            throw "Drive not accessible after mount"
        }
    } catch {
        Write-Log "PowerShell mount failed: $($_.Exception.Message)" "WARNING"

        Write-Log "Trying net use command as fallback..."
        $netUseCmd = "net use $drivePath `"$uncPath`" `"$StorageAccountKey`" /user:`"$workingCredFormat`" /persistent:yes"
        $netResult = cmd.exe /C $netUseCmd 2>&1
        Write-Log "Net use result: $netResult"

        Start-Sleep -Seconds 3
        if (Test-Path $drivePath) {
            Write-Log "Net use mount successful!"
        } else {
            Write-Log "Net use mount also failed" "ERROR"
            throw "All mount attempts failed"
        }
    }

    # Step 5: Copy backup files from file share to SQL Server
    Write-Log "=== STEP 5: Copying backup files from Azure File Share to SQL Server ==="
    Write-Log "Waiting 10 seconds before checking for backup files..."
    Start-Sleep -Seconds 10

    $mountedDrive = "$DriveLetter" + ":"
    $sourceFolder = "SQLBACKUPS"
    $destinationPath = "F:\SQLBackups"
    $sourcePath = "$mountedDrive\$sourceFolder"

    Write-Log "Starting backup file copy from Azure File Share to SQL Server..."
    Write-Log "Source: $sourcePath"
    Write-Log "Destination: $destinationPath"

    if (-not (Test-Path $mountedDrive)) {
        Write-Log "ERROR: Mounted drive '$mountedDrive' is not available!" "ERROR"
        throw "Mounted drive not available"
    }

    if (-not (Test-Path $sourcePath)) {
        Write-Log "Source folder '$sourcePath' does not exist! Backup files may not have been copied yet."
        Write-Log "SQL Server VM Configuration Completed (No backups to copy)"
        exit 0
    }

    if (-not (Test-Path $destinationPath)) {
        Write-Log "Creating destination directory: $destinationPath"
        New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
    }

    $backupFiles = Get-ChildItem -Path $sourcePath -Filter "*.bak" -File -ErrorAction SilentlyContinue

    if ($backupFiles.Count -eq 0) {
        Write-Log "No .bak files found in '$sourcePath'"
        Write-Log "SQL Server VM Configuration Completed (No .bak files to copy)"
        exit 0
    }

    Write-Log "Found $($backupFiles.Count) backup files to copy:"
    foreach ($file in $backupFiles) {
        Write-Log "  - $($file.Name) ($([math]::Round($file.Length/1MB, 2)) MB)"
    }

    $successCount = 0
    $errorCount = 0

    foreach ($file in $backupFiles) {
        try {
            $destinationFile = Join-Path $destinationPath $file.Name
            Write-Log "Copying: $($file.Name)..."

            if (Test-Path $destinationFile) {
                $destFile = Get-Item $destinationFile
                if ($destFile.Length -eq $file.Length) {
                    Write-Log "  [SKIPPED - Already exists with same size]"
                    continue
                }
            }

            Copy-Item -Path $file.FullName -Destination $destinationFile -Force

            if (Test-Path $destinationFile) {
                $copiedFile = Get-Item $destinationFile
                if ($copiedFile.Length -eq $file.Length) {
                    Write-Log "  [SUCCESS]"
                    $successCount++
                } else {
                    Write-Log "  [ERROR - Size mismatch]"
                    $errorCount++
                }
            } else {
                Write-Log "  [ERROR - File not found after copy]"
                $errorCount++
            }
        } catch {
            Write-Log "  [ERROR: $($_.Exception.Message)]"
            $errorCount++
        }
    }

    Write-Log "Copy Summary:"
    Write-Log "  Successfully copied: $successCount files"
    Write-Log "  Errors: $errorCount files"
    Write-Log "  Total files processed: $($backupFiles.Count)"

    # Step 6: Restore databases from local backup files
    Write-Log "=== STEP 6: Restoring databases from local backup files ==="
    $localBackupPath = "F:\SQLBackups"

    $localBackupFiles = Get-ChildItem -Path $localBackupPath -Filter "*.bak" -File -ErrorAction SilentlyContinue

    if ($localBackupFiles.Count -eq 0) {
        Write-Log "No backup files found in local directory for restore - skipping database restore"
    } else {
        Write-Log "Found $($localBackupFiles.Count) backup files for restore"

        Write-Log "Waiting for SQL Server service to be ready..."
        Start-Sleep -Seconds 30

        $sqlReady = $false
        for ($i = 1; $i -le 5; $i++) {
            try {
                Write-Log "Testing SQL Server connectivity (attempt $i/5)..."
                $testResult = sqlcmd -S localhost -U Yoda -P "$SqlPassword" -Q "SELECT @@VERSION" -b -t 10
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "SQL Server is ready"
                    $sqlReady = $true
                    break
                }
            } catch {
                Write-Log "SQL connectivity test failed: $($_.Exception.Message)" "WARNING"
            }
            Write-Log "SQL Server not ready, waiting 30 seconds..."
            Start-Sleep -Seconds 30
        }

        if (-not $sqlReady) {
            Write-Log "SQL Server did not become ready after 5 attempts" "ERROR"
            Write-Log "Skipping database restore - manual restore required"
        } else {
            Write-Log "Enabling advanced SQL Server options..."
            $enableCmd = "EXEC sp_configure 'show advanced options', 1; RECONFIGURE; EXEC sp_configure 'xp_cmdshell', 1; RECONFIGURE;"
            sqlcmd -S localhost -U Yoda -P "$SqlPassword" -Q "$enableCmd" -b -t 30

            if ($LASTEXITCODE -ne 0) {
                Write-Log "Failed to enable xp_cmdshell - continuing with restore anyway" "WARNING"
            } else {
                Write-Log "xp_cmdshell enabled successfully"
            }

            $databases = @(
                @{Name="EWN"; File="EWN_Current.bak"},
                @{Name="DataWarehouse"; File="Datawarehouse_Current.bak"},
                @{Name="Quartz"; File="Quartz_Current.bak"},
                @{Name="Rustici"; File="Rustici_Current.bak"},
                @{Name="TestDB"; File="TestDB_Current.bak"}
            )

            $restoredCount = 0
            foreach ($db in $databases) {
                $backupFile = "F:\SQLBackups\$($db.File)"

                if (Test-Path $backupFile) {
                    Write-Log "Restoring database: $($db.Name) from $backupFile"

                    $restoreCmd = "USE [master]; RESTORE DATABASE [$($db.Name)] FROM DISK = N'$backupFile' WITH FILE = 1, NOUNLOAD, REPLACE, STATS = 5"

                    Write-Log "Executing restore for $($db.Name)..."
                    $restoreResult = sqlcmd -S localhost -U Yoda -P "$SqlPassword" -Q "$restoreCmd" -b -t 1800

                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "SUCCESS: $($db.Name) restored successfully"
                        $restoredCount++
                    } else {
                        Write-Log "ERROR: $($db.Name) restore failed (Exit Code: $LASTEXITCODE)" "ERROR"
                        Write-Log "Restore output: $restoreResult" "ERROR"
                    }
                } else {
                    Write-Log "WARNING: Backup file not found: $backupFile" "WARNING"
                }
            }

            Write-Log "Disabling xp_cmdshell for security..."
            $disableCmd = "EXEC sp_configure 'xp_cmdshell', 0; RECONFIGURE; EXEC sp_configure 'show advanced options', 0; RECONFIGURE;"
            sqlcmd -S localhost -U Yoda -P "$SqlPassword" -Q "$disableCmd" -b -t 30
            Write-Log "xp_cmdshell disabled"

            Write-Log "Verifying restored databases..."
            $verifyCmd = "SELECT name, state_desc, create_date FROM sys.databases WHERE name IN ('EWN', 'DataWarehouse', 'Quartz', 'Rustici', 'TestDB')"
            $dbStatus = sqlcmd -S localhost -U Yoda -P "$SqlPassword" -Q "$verifyCmd" -b -t 30

            Write-Log "Database Status:"
            $dbStatus | ForEach-Object {
                if ($_ -and $_ -notmatch "rows affected" -and $_.Trim() -ne "") {
                    Write-Log "  $_"
                }
            }

            Write-Log "Successfully restored $restoredCount out of $($databases.Count) databases"
        }
    }

    Write-Log "=== SQL Server VM Configuration Completed Successfully ==="

} catch {
    Write-Log "Script execution failed: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}