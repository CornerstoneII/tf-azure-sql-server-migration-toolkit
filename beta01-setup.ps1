# BETA01 VM Setup Script
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
Write-Log "Storage Key Length: $($StorageAccountKey.Length) characters"

try {
    # Step 1: Network and Storage Validation
    Write-Log "=== STEP 1: Network and Storage Validation ==="
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

    # Step 2: Mount Azure File Share on BETA01
    Write-Log "=== STEP 2: Mounting Azure File Share on BETA01 ==="
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

    # Step 3: Copy backup files from BETA01 to file share
    Write-Log "=== STEP 3: Copying backup files from BETA01 to Azure File Share ==="
    $sourcePath = "F:\SQLBackups"
    $mountedDrive = "$DriveLetter" + ":"
    $destinationFolder = "SQLBACKUPS"
    $destinationPath = "$mountedDrive\$destinationFolder"

    Write-Log "Starting backup file copy from BETA01 to Azure File Share..."
    Write-Log "Source: $sourcePath"
    Write-Log "Destination: $destinationPath"

    # Verify source directory exists
    if (-not (Test-Path $sourcePath)) {
        Write-Log "Source path '$sourcePath' does not exist! Skipping backup copy."
        Write-Log "This is normal if BETA01 doesn't have SQL backup files."
        Write-Log "=== BETA01 VM Configuration Completed (No source directory) ==="
        exit 0
    }

    # Verify mounted drive exists
    if (-not (Test-Path $mountedDrive)) {
        Write-Log "ERROR: Mounted drive '$mountedDrive' is not available!" "ERROR"
        throw "Mounted drive not available"
    }

    # Verify destination folder exists
    if (-not (Test-Path $destinationPath)) {
        Write-Log "Destination folder '$destinationPath' does not exist! Creating it..."
        New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
        Write-Log "Destination folder created successfully"
    }

    # Get all .bak files from source
    $backupFiles = Get-ChildItem -Path $sourcePath -Filter "*.bak" -File -ErrorAction SilentlyContinue

    if ($backupFiles.Count -eq 0) {
        Write-Log "No .bak files found in '$sourcePath'"
        Write-Log "This is normal if BETA01 doesn't have backup files yet."
        Write-Log "=== BETA01 VM Configuration Completed (No .bak files found) ==="
        exit 0
    }

    Write-Log "Found $($backupFiles.Count) backup files to copy:"
    foreach ($file in $backupFiles) {
        Write-Log "  - $($file.Name) ($([math]::Round($file.Length/1MB, 2)) MB)"
    }

    # Copy each backup file with retry logic
    $successCount = 0
    $errorCount = 0

    foreach ($file in $backupFiles) {
        $copySuccess = $false

        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                $destinationFile = Join-Path $destinationPath $file.Name

                Write-Log "Copying: $($file.Name) (attempt $attempt)..."

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
                        Write-Log "  [RETRY - Size mismatch on attempt $attempt]"
                        if ($attempt -lt 3) { Start-Sleep -Seconds 5 }
                    }
                } else {
                    Write-Log "  [RETRY - File not found after copy on attempt $attempt]"
                    if ($attempt -lt 3) { Start-Sleep -Seconds 5 }
                }

            } catch {
                Write-Log "  [RETRY - Error on attempt $attempt : $($_.Exception.Message)]"
                if ($attempt -lt 3) { Start-Sleep -Seconds 10 }
            }
        }

        if (-not $copySuccess) {
            Write-Log "  [FINAL ERROR - All attempts failed for $($file.Name)]"
            $errorCount++
        }
    }

    Write-Log "Copy Summary:"
    Write-Log "  Successfully copied: $successCount files"
    Write-Log "  Errors: $errorCount files"
    Write-Log "  Total files processed: $($backupFiles.Count)"

    if ($successCount -gt 0) {
        Write-Log "✓ Successfully copied $successCount backup files to Azure File Share"
    }

    Write-Log "=== BETA01 VM Configuration Completed ==="

} catch {
    Write-Log "Script execution failed: $($_.Exception.Message)" "ERROR"
    exit 1
}