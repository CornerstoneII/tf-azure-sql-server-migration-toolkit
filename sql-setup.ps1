# SQL Server VM Setup Script - Complete Updated Version
param(
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory=$true)]
    [string]$StorageAccountKey,

    [Parameter(Mandatory=$true)]
    [string]$ShareName,

    [string]$DriveLetter = "Z"
)

# Enhanced logging function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Output $logMessage

    # Also write to a log file
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

try {
    # Step 1: Create SQLBackups directory on SQL Server
    Write-Log "=== STEP 1: Creating SQLBackups directory on SQL Server ==="
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

    # Use TLS 1.2 for download
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Invoke-WebRequest -Uri "https://aka.ms/ssmsfullsetup" -OutFile $ssmsPath -UseBasicParsing -TimeoutSec 300
    Write-Log "SSMS installer downloaded successfully"

    Write-Log "Starting SSMS installation (this may take several minutes)..."
    $installProcess = Start-Process $ssmsPath -ArgumentList '/Quiet /Install' -Wait -PassThru

    if ($installProcess.ExitCode -eq 0) {
        Write-Log "SSMS installation completed successfully"
    } else {
        Write-Log "SSMS installation completed with exit code: $($installProcess.ExitCode)" "WARNING"
    }

    # Clean up installer
    if (Test-Path $ssmsPath) {
        Remove-Item $ssmsPath -Force -ErrorAction SilentlyContinue
    }

    # Step 3: Network and Storage Validation
    Write-Log "=== STEP 3: Network and Storage Validation ==="
    $fqdn = "$StorageAccountName.file.core.windows.net"

    Write-Log "Testing network connectivity to $fqdn on port 445..."
    $connectTest = Test-NetConnection -ComputerName $fqdn -Port 445 -WarningAction SilentlyContinue

    if ($connectTest.TcpTestSucceeded) {
        Write-Log "✓ Port 445 connectivity: SUCCESS"
    } else {
        Write-Log "✗ Port 445 connectivity: FAILED - Check firewall settings" "ERROR"
        Write-Log "This could be due to corporate firewall or ISP blocking port 445" "ERROR"
        # Don't exit - try to continue anyway
    }

    # Test storage account authentication
    Write-Log "Testing storage account authentication..."
    $uncPath = "\\$fqdn\$ShareName"
    $secureKey = ConvertTo-SecureString -String $StorageAccountKey -AsPlainText -Force

    # Try different credential formats
    $credentialFormats = @("AZURE\$StorageAccountName", "$StorageAccountName")
    $authSuccess = $false
    $workingCredFormat = $null

    foreach ($credFormat in $credentialFormats) {
        try {
            Write-Log "Testing authentication with credential format: $credFormat"
            $testCred = New-Object System.Management.Automation.PSCredential($credFormat, $secureKey)
            $testDrive = New-PSDrive -Name "TEMP_AUTH_TEST" -PSProvider FileSystem -Root $uncPath -Credential $testCred -ErrorAction Stop
            Remove-PSDrive -Name "TEMP_AUTH_TEST" -Force

            Write-Log "✓ Authentication successful with: $credFormat"
            $authSuccess = $true
            $workingCredFormat = $credFormat
            break
        } catch {
            Write-Log "Authentication failed with $credFormat : $($_.Exception.Message)" "WARNING"
        }
    }

    if (-not $authSuccess) {
        Write-Log "✗ All authentication attempts failed!" "ERROR"
        Write-Log "This usually indicates incorrect storage key or network issues" "ERROR"
        exit 1
    }

    # Step 4: Mount Azure File Share
    Write-Log "=== STEP 4: Mounting Azure File Share ==="
    $drivePath = "$DriveLetter" + ":"

    Write-Log "Attempting to mount Azure File Share..."
    Write-Log "UNC Path: $uncPath"
    Write-Log "Drive Path: $drivePath"
    Write-Log "Using working credential format: $workingCredFormat"

    # Clean up any existing mappings
    Write-Log "Cleaning up existing drive mappings for $DriveLetter..."

    # Remove PowerShell drive
    try {
        Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue | Remove-PSDrive -Force -ErrorAction SilentlyContinue
        Write-Log "Cleaned up existing PowerShell drive"
    } catch {
        Write-Log "No PowerShell drive to clean up"
    }

    # Remove net use mapping
    try {
        $netUseOutput = cmd.exe /C "net use $drivePath /delete /y" 2>&1
        Write-Log "Net use delete output: $netUseOutput"
        Start-Sleep -Seconds 2
    } catch {
        Write-Log "No existing net use mapping to clean up"
    }

    # Mount using the working credential format
    Write-Log "Mounting drive using PowerShell with credential format: $workingCredFormat"
    $credential = New-Object System.Management.Automation.PSCredential($workingCredFormat, $secureKey)

    try {
        New-PSDrive -Name $DriveLetter -PSProvider FileSystem -Root $uncPath -Credential $credential -Persist -ErrorAction Stop

        # Wait and verify
        Start-Sleep -Seconds 5

        if (Test-Path $drivePath) {
            $items = Get-ChildItem $drivePath -ErrorAction SilentlyContinue
            Write-Log "✓ Azure File Share successfully mounted to $DriveLetter`: drive"
            Write-Log "Items in root of share: $($items.Count)"

            # Verify/Create SQLBACKUPS folder
            $sqlBackupsSharePath = Join-Path $drivePath "SQLBACKUPS"
            if (Test-Path $sqlBackupsSharePath) {
                Write-Log "✓ SQLBACKUPS folder found in share"
            } else {
                Write-Log "Creating SQLBACKUPS folder in share..."
                New-Item -Path $sqlBackupsSharePath -ItemType Directory -Force | Out-Null
                Write-Log "✓ SQLBACKUPS folder created in share"
            }
        } else {
            Write-Log "✗ Drive mounted but not accessible" "ERROR"
            throw "Drive not accessible after mount"
        }
    } catch {
        Write-Log "PowerShell mount failed: $($_.Exception.Message)" "WARNING"

        # Fall back to net use command
        Write-Log "Trying net use command as fallback..."
        $netUseCmd = "net use $drivePath `"$uncPath`" `"$StorageAccountKey`" /user:`"$workingCredFormat`" /persistent:yes"
        $netResult = cmd.exe /C $netUseCmd 2>&1
        Write-Log "Net use result: $netResult"

        Start-Sleep -Seconds 3
        if (Test-Path $drivePath) {
            Write-Log "✓ Net use mount successful!"
        } else {
            Write-Log "✗ Net use mount also failed" "ERROR"
            throw "All mount attempts failed"
        }
    }

    # Step 5: IMPROVED - Copy backup files with smart waiting and retry logic
    Write-Log "=== STEP 5: Copying backup files from Azure File Share to SQL Server ==="

    $mountedDrive = "$DriveLetter" + ":"
    $sourceFolder = "SQLBACKUPS"
    $destinationPath = "F:\SQLBackups"
    $sourcePath = "$mountedDrive\$sourceFolder"

    Write-Log "Starting backup file copy from Azure File Share to SQL Server..."
    Write-Log "Source: $sourcePath"
    Write-Log "Destination: $destinationPath"

    # Verify mounted drive exists
    if (-not (Test-Path $mountedDrive)) {
        Write-Log "ERROR: Mounted drive '$mountedDrive' is not available!" "ERROR"
        throw "Mounted drive not available"
    }

    # Create destination directory if it doesn't exist
    if (-not (Test-Path $destinationPath)) {
        Write-Log "Creating destination directory: $destinationPath"
        New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
    }

    # IMPROVED: Wait for BETA01 with smart retry logic instead of fixed wait time
    Write-Log "Waiting for BETA01 to copy backup files to the share..."
    $maxWaitTime = 300  # 5 minutes maximum wait
    $checkInterval = 30  # Check every 30 seconds
    $waitTime = 0
    $filesFound = $false
    $backupFiles = @()

    while ($waitTime -lt $maxWaitTime) {
        # Check if source folder exists
        if (Test-Path $sourcePath) {
            # Check if there are .bak files
            $backupFiles = Get-ChildItem -Path $sourcePath -Filter "*.bak" -File -ErrorAction SilentlyContinue

            if ($backupFiles.Count -gt 0) {
                Write-Log "✓ Found $($backupFiles.Count) backup files in share after $waitTime seconds"
                $filesFound = $true
                break
            } else {
                Write-Log "SQLBACKUPS folder exists but no .bak files found yet. Waiting..."
            }
        } else {
            Write-Log "SQLBACKUPS folder not found in share yet. Waiting..."
        }

        Start-Sleep -Seconds $checkInterval
        $waitTime += $checkInterval
        Write-Log "Waited $waitTime seconds for backup files..."
    }

    if (-not $filesFound) {
        Write-Log "No backup files found after waiting $maxWaitTime seconds."
        Write-Log "This could mean:"
        Write-Log "  1. BETA01 doesn't have backup files"
        Write-Log "  2. BETA01 script failed to copy files"
        Write-Log "  3. Network issues prevented the copy"
        Write-Log "Azure File Share is mounted and ready for future use."
        Write-Log "=== SQL Server VM Configuration Completed (No backup files available) ==="
        exit 0
    }

    # At this point, we know there are backup files to copy
    Write-Log "Found $($backupFiles.Count) backup files to copy:"
    foreach ($file in $backupFiles) {
        Write-Log "  - $($file.Name) ($([math]::Round($file.Length/1MB, 2)) MB)"
    }

    # Copy each backup file with retry logic
    $successCount = 0
    $errorCount = 0

    foreach ($file in $backupFiles) {
        $copySuccess = $false
        $maxRetries = 3

        for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
            try {
                $destinationFile = Join-Path $destinationPath $file.Name

                Write-Log "Copying: $($file.Name) (attempt $attempt of $maxRetries)..."

                # Check if file already exists and compare sizes
                if (Test-Path $destinationFile) {
                    $destFile = Get-Item $destinationFile
                    if ($destFile.Length -eq $file.Length) {
                        Write-Log "  [SKIPPED - Already exists with same size]"
                        $copySuccess = $true
                        break
                    }
                }

                Copy-Item -Path $file.FullName -Destination $destinationFile -Force

                # Verify copy was successful
                Start-Sleep -Seconds 2
                if (Test-Path $destinationFile) {
                    $copiedFile = Get-Item $destinationFile
                    if ($copiedFile.Length -eq $file.Length) {
                        Write-Log "  [SUCCESS]"
                        $successCount++
                        $copySuccess = $true
                        break
                    } else {
                        Write-Log "  [RETRY - Size mismatch: expected $($file.Length), got $($copiedFile.Length)]"
                        if ($attempt -lt $maxRetries) {
                            Start-Sleep -Seconds 5
                        }
                    }
                } else {
                    Write-Log "  [RETRY - File not found after copy]"
                    if ($attempt -lt $maxRetries) {
                        Start-Sleep -Seconds 5
                    }
                }

            } catch {
                Write-Log "  [RETRY - Error on attempt $attempt : $($_.Exception.Message)]"
                if ($attempt -lt $maxRetries) {
                    Start-Sleep -Seconds 10
                }
            }
        }

        if (-not $copySuccess) {
            Write-Log "  [FINAL ERROR - All $maxRetries attempts failed for $($file.Name)]"
            $errorCount++
        }
    }

    Write-Log "Copy Summary:"
    Write-Log "  Successfully copied: $successCount files"
    Write-Log "  Errors: $errorCount files"
    Write-Log "  Total files processed: $($backupFiles.Count)"

    if ($successCount -gt 0) {
        Write-Log "✓ Successfully copied backup files to local SQL Server storage"
    } else {
        Write-Log "✗ No files were successfully copied to local storage"
        Write-Log "Files are still available in the Azure File Share at: $sourcePath"
    }

    Write-Log "=== SQL Server VM Configuration Completed Successfully ==="

} catch {
    Write-Log "Script execution failed: $($_.Exception.Message)" "ERROR"
    exit 1
}