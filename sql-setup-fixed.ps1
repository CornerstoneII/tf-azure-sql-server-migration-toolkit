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
    # Write-Log "=== STEP 3: Network and Storage Validation ==="
    # $fqdn = "$StorageAccountName.file.core.windows.net"
    # $uncPath = "\\$fqdn\$ShareName"

    # Write-Log "Testing network connectivity to $fqdn on port 445..."
    # $connectTest = Test-NetConnection -ComputerName $fqdn -Port 445 -WarningAction SilentlyContinue

    # if ($connectTest.TcpTestSucceeded) {
    #     Write-Log "Port 445 connectivity: SUCCESS"
    # } else {
    #     Write-Log "Port 445 connectivity: FAILED" "WARNING"
    # }

    # # Test storage account authentication
    # Write-Log "Testing storage account authentication..."
    # $secureKey = ConvertTo-SecureString -String $StorageAccountKey -AsPlainText -Force
    # $credentialFormats = @("AZURE\$StorageAccountName", "$StorageAccountName")
    # $authSuccess = $false
    # $workingCredFormat = $null

    # foreach ($credFormat in $credentialFormats) {
    #     try {
    #         Write-Log "Testing authentication with credential format: $credFormat"
    #         $testCred = New-Object System.Management.Automation.PSCredential($credFormat, $secureKey)
    #         $testDrive = New-PSDrive -Name "TEMP_AUTH_TEST" -PSProvider FileSystem -Root $uncPath -Credential $testCred -ErrorAction Stop
    #         Remove-PSDrive -Name "TEMP_AUTH_TEST" -Force

    #         Write-Log "Authentication successful with: $credFormat"
    #         $authSuccess = $true
    #         $workingCredFormat = $credFormat
    #         break
    #     } catch {
    #         Write-Log "Authentication failed with $credFormat : $($_.Exception.Message)" "WARNING"
    #     }
    # }

    # if (-not $authSuccess) {
    #     Write-Log "All authentication attempts failed!" "ERROR"
    #     Write-Log "This usually indicates incorrect storage key or network issues" "ERROR"
    #     exit 1
    # }

    # Step 4: Mount Azure File Share
    # Write-Log "=== STEP 4: Mounting Azure File Share ==="
    # $drivePath = "$DriveLetter" + ":"

    # Write-Log "Attempting to mount Azure File Share..."
    # Write-Log "UNC Path: $uncPath"
    # Write-Log "Drive Path: $drivePath"

    # # Clean up existing mappings
    # try {
    #     Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue | Remove-PSDrive -Force -ErrorAction SilentlyContinue
    #     Write-Log "Cleaned up existing PowerShell drive"
    # } catch {
    #     Write-Log "No PowerShell drive to clean up"
    # }

    # try {
    #     $netUseOutput = cmd.exe /C "net use $drivePath /delete /y" 2>&1
    #     Write-Log "Net use delete output: $netUseOutput"
    #     Start-Sleep -Seconds 2
    # } catch {
    #     Write-Log "No existing net use mapping to clean up"
    # }

    # # Mount using the working credential format
    # $credential = New-Object System.Management.Automation.PSCredential($workingCredFormat, $secureKey)

    # try {
    #     New-PSDrive -Name $DriveLetter -PSProvider FileSystem -Root $uncPath -Credential $credential -Persist -ErrorAction Stop
    #     Start-Sleep -Seconds 5

    #     if (Test-Path $drivePath) {
    #         $items = Get-ChildItem $drivePath -ErrorAction SilentlyContinue
    #         Write-Log "Azure File Share successfully mounted to $DriveLetter drive"
    #         Write-Log "Items in root of share: $($items.Count)"

    #         $sqlBackupsSharePath = Join-Path $drivePath "SQLBACKUPS"
    #         if (Test-Path $sqlBackupsSharePath) {
    #             Write-Log "SQLBACKUPS folder found in share"
    #         } else {
    #             Write-Log "Creating SQLBACKUPS folder in share..."
    #             New-Item -Path $sqlBackupsSharePath -ItemType Directory -Force | Out-Null
    #             Write-Log "SQLBACKUPS folder created in share"
    #         }
    #     } else {
    #         Write-Log "Drive mounted but not accessible" "ERROR"
    #         throw "Drive not accessible after mount"
    #     }
    # } catch {
    #     Write-Log "PowerShell mount failed: $($_.Exception.Message)" "WARNING"

    #     Write-Log "Trying net use command as fallback..."
    #     $netUseCmd = "net use $drivePath `"$uncPath`" `"$StorageAccountKey`" /user:`"$workingCredFormat`" /persistent:yes"
    #     $netResult = cmd.exe /C $netUseCmd 2>&1
    #     Write-Log "Net use result: $netResult"

    #     Start-Sleep -Seconds 3
    #     if (Test-Path $drivePath) {
    #         Write-Log "Net use mount successful!"
    #     } else {
    #         Write-Log "Net use mount also failed" "ERROR"
    #         throw "All mount attempts failed"
    #     }
    # }

    # Step 5: Copy backup files from file share to SQL Server
    # Write-Log "=== STEP 5: Copying backup files from Azure File Share to SQL Server ==="
    # Write-Log "Waiting 10 seconds before checking for backup files..."
    # Start-Sleep -Seconds 10

    # $mountedDrive = "$DriveLetter" + ":"
    # $sourceFolder = "SQLBACKUPS"
    # $destinationPath = "F:\SQLBackups"
    # $sourcePath = "$mountedDrive\$sourceFolder"

    # Write-Log "Starting backup file copy from Azure File Share to SQL Server..."
    # Write-Log "Source: $sourcePath"
    # Write-Log "Destination: $destinationPath"

    # if (-not (Test-Path $mountedDrive)) {
    #     Write-Log "ERROR: Mounted drive '$mountedDrive' is not available!" "ERROR"
    #     throw "Mounted drive not available"
    # }

    # if (-not (Test-Path $sourcePath)) {
    #     Write-Log "Source folder '$sourcePath' does not exist! Backup files may not have been copied yet."
    #     Write-Log "SQL Server VM Configuration Completed (No backups to copy)"
    #     exit 0
    # }

    # if (-not (Test-Path $destinationPath)) {
    #     Write-Log "Creating destination directory: $destinationPath"
    #     New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
    # }

    # $backupFiles = Get-ChildItem -Path $sourcePath -Filter "*.bak" -File -ErrorAction SilentlyContinue

    # if ($backupFiles.Count -eq 0) {
    #     Write-Log "No .bak files found in '$sourcePath'"
    #     Write-Log "SQL Server VM Configuration Completed (No .bak files to copy)"
    #     exit 0
    # }

    # Write-Log "Found $($backupFiles.Count) backup files to copy:"
    # foreach ($file in $backupFiles) {
    #     Write-Log "  - $($file.Name) ($([math]::Round($file.Length/1MB, 2)) MB)"
    # }

    # $successCount = 0
    # $errorCount = 0

    # foreach ($file in $backupFiles) {
    #     try {
    #         $destinationFile = Join-Path $destinationPath $file.Name
    #         Write-Log "Copying: $($file.Name)..."

    #         if (Test-Path $destinationFile) {
    #             $destFile = Get-Item $destinationFile
    #             if ($destFile.Length -eq $file.Length) {
    #                 Write-Log "  [SKIPPED - Already exists with same size]"
    #                 continue
    #             }
    #         }

    #         Copy-Item -Path $file.FullName -Destination $destinationFile -Force

    #         if (Test-Path $destinationFile) {
    #             $copiedFile = Get-Item $destinationFile
    #             if ($copiedFile.Length -eq $file.Length) {
    #                 Write-Log "  [SUCCESS]"
    #                 $successCount++
    #             } else {
    #                 Write-Log "  [ERROR - Size mismatch]"
    #                 $errorCount++
    #             }
    #         } else {
    #             Write-Log "  [ERROR - File not found after copy]"
    #             $errorCount++
    #         }
    #     } catch {
    #         Write-Log "  [ERROR: $($_.Exception.Message)]"
    #         $errorCount++
    #     }
    # }

    # Write-Log "Copy Summary:"
    # Write-Log "  Successfully copied: $successCount files"
    # Write-Log "  Errors: $errorCount files"
    # Write-Log "  Total files processed: $($backupFiles.Count)"

    # Step 6: Enable Azure AD Authentication and Create Managed Identity Login
    Write-Log "=== STEP 6: Enable Azure AD Authentication ==="
    $useManagedIdentity = $true  # Default to trying managed identity

    # Configure Azure AD authentication using SQL Server Configuration Manager PowerShell
    Write-Log "Configuring SQL Server for Azure AD authentication..."

    # Check and configure SQL Server authentication mode first
    Write-Log "Checking SQL Server authentication mode..."
    $checkAuthModeCmd = @"
DECLARE @AuthenticationMode INT
EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',
N'Software\Microsoft\MSSQLServer\MSSQLServer',
N'LoginMode', @AuthenticationMode OUTPUT

SELECT CASE @AuthenticationMode
WHEN 1 THEN 'Windows authentication'
WHEN 2 THEN 'Mixed Mode'
ELSE 'Unknown'
END as [Authentication Mode], @AuthenticationMode as [Mode Value]
"@

    $authModeResult = sqlcmd -S localhost -U Yoda -P "$SqlPassword" -Q "$checkAuthModeCmd" -h -1 -b -t 30
    Write-Log "Current authentication mode: $authModeResult"

    # Set to Mixed Mode if not already (required for Azure AD integration)
    if ($authModeResult -notlike "*Mixed Mode*") {
        Write-Log "Setting SQL Server to Mixed Mode authentication..."
        $setMixedModeCmd = @"
EXEC master.dbo.xp_instance_regwrite N'HKEY_LOCAL_MACHINE',
N'Software\Microsoft\MSSQLServer\MSSQLServer',
N'LoginMode', REG_DWORD, 2
"@
        $mixedModeResult = sqlcmd -S localhost -U Yoda -P "$SqlPassword" -Q "$setMixedModeCmd" -b -t 30
        if ($LASTEXITCODE -eq 0) {
            Write-Log "SQL Server set to Mixed Mode - restart required"
            $requiresRestart = $true
        } else {
            Write-Log "Failed to set Mixed Mode authentication" "ERROR"
            Write-Log "Mixed mode result: $mixedModeResult" "ERROR"
            exit 1
        }
    } else {
        Write-Log "SQL Server already in Mixed Mode"
        $requiresRestart = $false
    }

    # Enable contained database authentication
    $enableAADCmd = @"
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'contained database authentication', 1;
RECONFIGURE;
EXEC sp_configure 'show advanced options', 0;
RECONFIGURE;
"@

    $aadResult = sqlcmd -S localhost -U Yoda -P "$SqlPassword" -Q "$enableAADCmd" -b -t 60
    if ($LASTEXITCODE -eq 0) {
        Write-Log "SQL Server contained database authentication enabled"
    } else {
        Write-Log "Failed to enable contained database authentication" "ERROR"
        Write-Log "Command output: $aadResult" "ERROR"
        exit 1
    }

    # Configure managed identity as Azure AD admin using REST API
    Write-Log "Configuring managed identity as Azure AD admin via REST API..."

    try {
        # Get access token using managed identity
        $tokenResponse = Invoke-RestMethod -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/" -Headers @{Metadata="true"} -Method GET
        $accessToken = $tokenResponse.access_token

        # Get managed identity details
        $miResponse = Invoke-RestMethod -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/" -Headers @{Metadata="true"} -Method GET
        $subscriptionId = "52f9cc50-7e1e-4e82-b8c3-da2757e84a48"
        $resourceGroup = "sql-pkr-img"
        $sqlVmName = "vm-usaw02-a22"
        $tenantId = "5469d93f-4b40-4153-b860-279b2c3d45e7"
        $managedIdentityPrincipalId = "9fed00ed-fee3-464d-8cba-a83aa6b04dbf"

        # Configure Azure AD admin via REST API
        $headers = @{
            'Authorization' = "Bearer $accessToken"
            'Content-Type' = 'application/json'
        }

        $body = @{
            properties = @{
                administratorType = "ActiveDirectory"
                login = "mi-sql-tst-win"
                sid = $managedIdentityPrincipalId
                tenantId = $tenantId
            }
        } | ConvertTo-Json -Depth 3

        $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.SqlVirtualMachine/sqlVirtualMachines/$sqlVmName/administrators/ActiveDirectory?api-version=2022-02-01"

        Write-Log "Making REST API call to set Azure AD admin..."
        $adminResponse = Invoke-RestMethod -Uri $uri -Method PUT -Headers $headers -Body $body
        Write-Log "Azure AD admin configured successfully via REST API"
        $requiresRestart = $true

    } catch {
        Write-Log "Failed to configure Azure AD admin via REST API: $($_.Exception.Message)" "WARNING"
        Write-Log "Azure AD admin configuration may need to be done manually" "WARNING"
    }

    # Restart SQL Server if Mixed Mode was changed or if Azure AD configuration requires it
    if ($requiresRestart) {
        Write-Log "Restarting SQL Server service to apply authentication mode and Azure AD changes..."
        try {
            Restart-Service -Name "MSSQLSERVER" -Force
            Start-Sleep -Seconds 30

            # Wait for SQL Server to come back online
            $retryCount = 0
            $maxRetries = 10
            do {
                $retryCount++
                Write-Log "Waiting for SQL Server to restart (attempt $retryCount/$maxRetries)..."
                Start-Sleep -Seconds 15
                $testConn = sqlcmd -S localhost -U Yoda -P "$SqlPassword" -Q "SELECT @@VERSION" -b -t 10 2>&1
            } while ($LASTEXITCODE -ne 0 -and $retryCount -lt $maxRetries)

            if ($LASTEXITCODE -eq 0) {
                Write-Log "SQL Server restarted successfully with Mixed Mode and Azure AD configuration"
            } else {
                Write-Log "Failed to restart SQL Server properly" "ERROR"
                exit 1
            }
        } catch {
            Write-Log "Failed to restart SQL Server: $($_.Exception.Message)" "ERROR"
            exit 1
        }
    } else {
        Write-Log "No SQL Server restart required - Mixed Mode already enabled"
    }

    # Wait for Azure AD configuration to take effect
    Write-Log "Waiting for SQL Server service to be ready for Azure AD configuration..."
    Start-Sleep -Seconds 30

    # Test if managed identity is already configured as Azure AD admin
    Write-Log "Testing managed identity Azure AD authentication..."
    $testMICmd = "SELECT SUSER_NAME(), @@VERSION"
    $miTestResult = sqlcmd -S localhost -G -Q "$testMICmd" -b -t 60 -C 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Log "Managed identity authentication successful - already configured as Azure AD admin"
        Write-Log "Managed identity details: $miTestResult"
    } else {
        Write-Log "Managed identity not yet configured as admin, checking if login exists..."

        # Check if managed identity login already exists
        $checkMILoginCmd = "SELECT name FROM sys.server_principals WHERE type = 'E' AND name = 'mi-sql-tst-win'"
        $checkResult = sqlcmd -S localhost -U Yoda -P "$SqlPassword" -Q "$checkMILoginCmd" -h -1 -b -t 30

        if ($checkResult -like "*mi-sql-tst-win*") {
            Write-Log "Managed identity login already exists"
        } else {
            # Create managed identity login using Yoda account (without sysadmin privileges)
            Write-Log "Creating managed identity login for web application access..."
            $createMILoginCmd = @"
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE type = 'E' AND name = 'mi-sql-tst-win')
BEGIN
    CREATE LOGIN [mi-sql-tst-win] FROM EXTERNAL PROVIDER;
    -- Note: No sysadmin role - will be granted db-specific READ/WRITE access later
END;
"@

            $miResult = sqlcmd -S localhost -U Yoda -P "$SqlPassword" -Q "$createMILoginCmd" -b -t 60 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Managed identity login created successfully"
            } else {
                Write-Log "Failed to create managed identity login - detailed error:" "ERROR"
                Write-Log "Command output: $miResult" "ERROR"
                Write-Log "This may be because Azure AD admin is not yet fully configured" "WARNING"
                Write-Log "Falling back to Yoda authentication for database operations" "WARNING"
                $useManagedIdentity = $false
            }
        }

        # Final test of managed identity authentication
        if ($useManagedIdentity) {
            Write-Log "Testing managed identity authentication after configuration..."
            $finalTestResult = sqlcmd -S localhost -G -Q "SELECT SUSER_NAME()" -b -t 30 -C 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Managed identity authentication confirmed working"
            } else {
                Write-Log "Managed identity authentication still failing, using Yoda fallback" "WARNING"
                Write-Log "Error details: $finalTestResult" "WARNING"
                $useManagedIdentity = $false
            }
        }
    }

    # Apply SQL Server configuration settings
    Write-Log "Applying SQL Server configuration settings..."
    $serverSettingsCmd = @"
EXECUTE sp_configure 'show advanced options', 1;
RECONFIGURE WITH OVERRIDE;
EXECUTE sp_configure 'nested triggers', 1;
RECONFIGURE;
EXEC sp_configure 'remote admin connections', 1;
RECONFIGURE;
EXEC sys.sp_configure N'cost threshold for parallelism', N'50';
RECONFIGURE;
EXECUTE sp_configure 'show advanced options', 0;
RECONFIGURE WITH OVERRIDE;
"@

    $settingsResult = sqlcmd -S localhost -U Yoda -P "$SqlPassword" -Q "$serverSettingsCmd" -b -t 60
    if ($LASTEXITCODE -eq 0) {
        Write-Log "SQL Server configuration settings applied successfully"
    } else {
        Write-Log "Failed to apply SQL Server configuration settings" "WARNING"
        Write-Log "Settings output: $settingsResult" "WARNING"
    }

    # Step 7: Restore databases using Yoda account
    Write-Log "=== STEP 7: Restoring databases using Yoda account ==="
    $localBackupPath = "F:\SQLBackups"

    $localBackupFiles = Get-ChildItem -Path $localBackupPath -Filter "*.bak" -File -ErrorAction SilentlyContinue

    if ($localBackupFiles.Count -eq 0) {
        Write-Log "No backup files found in local directory for restore - skipping database restore"
    } else {
        Write-Log "Found $($localBackupFiles.Count) backup files for restore"

        Write-Log "Waiting for SQL Server service to be ready..."
        Start-Sleep -Seconds 30

        # Test SQL Server connectivity with Yoda account for database restoration
        $sqlReady = $false
        for ($i = 1; $i -le 5; $i++) {
            try {
                Write-Log "Testing SQL Server connectivity with Yoda account (attempt $i/5)..."
                $testResult = sqlcmd -S localhost -U Yoda -P "$SqlPassword" -Q "SELECT SUSER_NAME(), @@VERSION" -b -t 30 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "SQL Server ready - Yoda authentication successful"
                    $sqlReady = $true
                    break
                } else {
                    Write-Log "Yoda authentication failed: $testResult" "WARNING"
                }
            } catch {
                Write-Log "SQL connectivity test failed: $($_.Exception.Message)" "WARNING"
            }
            if ($i -lt 5) {
                Write-Log "SQL Server not ready, waiting 10 seconds..."
                Start-Sleep -Seconds 10
            }
        }

        if (-not $sqlReady) {
            Write-Log "CRITICAL ERROR: SQL Server not ready for Yoda authentication after 5 attempts" "ERROR"
            Write-Log "Database restoration cannot proceed" "ERROR"
            exit 1
        } else {
            Write-Log "Enabling advanced SQL Server options using Yoda account..."
            $enableCmd = "EXEC sp_configure 'show advanced options', 1; RECONFIGURE; EXEC sp_configure 'xp_cmdshell', 1; RECONFIGURE;"
            $enableResult = sqlcmd -S localhost -U Yoda -P "$SqlPassword" -Q "$enableCmd" -b -t 30 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "xp_cmdshell enabled successfully using Yoda account"
            } else {
                Write-Log "Failed to enable xp_cmdshell using Yoda account: $enableResult" "ERROR"
                exit 1
            }

            $databases = @(
                @{Name="EWN"; File="EWN_Current.bak"},
                @{Name="DataWarehouse"; File="Datawarehouse_Current.bak"},
                @{Name="Quartz"; File="Quartz_Current.bak"},
                @{Name="Rustici"; File="Rustici_Current.bak"},
                @{Name="TestDB"; File="TestDB_Current.bak"}
            )

            # Databases that should have managed identity permissions (per 03 Grant Permissions SQL file)
            $databasesWithMIAccess = @("EWN", "DataWarehouse", "Quartz", "Rustici")

            $restoredCount = 0
            foreach ($db in $databases) {
                $backupFile = "F:\SQLBackups\$($db.File)"

                if (Test-Path $backupFile) {
                    Write-Log "Restoring database: $($db.Name) from $backupFile using YODA account"

                    $restoreCmd = "USE [master]; RESTORE DATABASE [$($db.Name)] FROM DISK = N'$backupFile' WITH FILE = 1, NOUNLOAD, REPLACE, STATS = 5"

                    Write-Log "Executing restore for $($db.Name) using Yoda account..."
                    $restoreResult = sqlcmd -S localhost -U Yoda -P "$SqlPassword" -Q "$restoreCmd" -b -t 1800 2>&1

                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "SUCCESS: $($db.Name) restored successfully by YODA"
                        $restoredCount++

                        # Grant managed identity permissions only for databases specified in 03 Grant Permissions SQL file
                        if ($databasesWithMIAccess -contains $db.Name) {
                            Write-Log "Granting managed identity READ/WRITE/EXECUTE access to $($db.Name)..."
                            $grantAccessCmd = @"
USE [$($db.Name)];
-- Create user if not exists
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE type = 'E' AND name = 'mi-sql-tst-win')
BEGIN
    CREATE USER [mi-sql-tst-win] FROM LOGIN [mi-sql-tst-win];
END;

-- Grant read/write permissions
ALTER ROLE [db_datareader] ADD MEMBER [mi-sql-tst-win];
ALTER ROLE [db_datawriter] ADD MEMBER [mi-sql-tst-win];

-- Grant execute permission (create role if it doesn't exist)
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'db_executor' AND type = 'R')
BEGIN
    CREATE ROLE [db_executor];
    GRANT EXECUTE TO [db_executor];
END;
ALTER ROLE [db_executor] ADD MEMBER [mi-sql-tst-win];
"@

                            $accessResult = sqlcmd -S localhost -U Yoda -P "$SqlPassword" -Q "$grantAccessCmd" -b -t 60 2>&1
                            if ($LASTEXITCODE -eq 0) {
                                Write-Log "SUCCESS: Managed identity granted READ/WRITE/EXECUTE access to $($db.Name)"
                            } else {
                                Write-Log "WARNING: Failed to grant managed identity access to $($db.Name): $accessResult" "WARNING"
                            }
                        } else {
                            Write-Log "SKIPPED: $($db.Name) does not require managed identity access per configuration"
                        }

                    } else {
                        Write-Log "ERROR: $($db.Name) restore failed using Yoda account (Exit Code: $LASTEXITCODE)" "ERROR"
                        Write-Log "Restore output: $restoreResult" "ERROR"
                        exit 1
                    }
                } else {
                    Write-Log "WARNING: Backup file not found: $backupFile" "WARNING"
                }
            }

            Write-Log "Disabling xp_cmdshell for security using Yoda account..."
            $disableCmd = "EXEC sp_configure 'xp_cmdshell', 0; RECONFIGURE; EXEC sp_configure 'show advanced options', 0; RECONFIGURE;"
            $disableResult = sqlcmd -S localhost -U Yoda -P "$SqlPassword" -Q "$disableCmd" -b -t 30 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "xp_cmdshell disabled successfully for security"
            } else {
                Write-Log "Failed to disable xp_cmdshell: $disableResult" "WARNING"
            }

            Write-Log "Verifying restored databases using Yoda account..."
            $verifyCmd = "SELECT name, state_desc, create_date FROM sys.databases WHERE name IN ('EWN', 'DataWarehouse', 'Quartz', 'Rustici', 'TestDB')"
            $dbStatus = sqlcmd -S localhost -U Yoda -P "$SqlPassword" -Q "$verifyCmd" -b -t 30 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-Log "Database Status:"
                $dbStatus | ForEach-Object {
                    if ($_ -and $_ -notmatch "rows affected" -and $_.Trim() -ne "") {
                        Write-Log "  $_"
                    }
                }
                Write-Log "Successfully restored $restoredCount out of $($databases.Count) databases using YODA account"
                
                # Test managed identity connectivity only for databases with MI access
                Write-Log "Testing managed identity connectivity to databases with configured access..."
                foreach ($dbName in $databasesWithMIAccess) {
                    $testCmd = "USE [$dbName]; SELECT DB_NAME() as CurrentDB, USER_NAME() as CurrentUser, IS_MEMBER('db_datareader') as CanRead, IS_MEMBER('db_datawriter') as CanWrite, IS_MEMBER('db_executor') as CanExecute"
                    Write-Log "Testing managed identity access to $dbName..."
                    $testResult = sqlcmd -S localhost -G -Q "$testCmd" -b -t 30 -C 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "SUCCESS: Managed identity can access $dbName"
                        Write-Log "  Access details: $testResult"
                    } else {
                        Write-Log "WARNING: Managed identity cannot access ${dbName}" "WARNING"
                        Write-Log "  Error details: $testResult" "WARNING"
                    }
                }
                Write-Log "Note: TestDB does not have managed identity access (not required per configuration)"
            } else {
                Write-Log "Failed to verify databases: $dbStatus" "ERROR"
                exit 1
            }
        }
    }

    # Step 8: Create Azure AD Group Logins and Server Roles
    Write-Log "=== STEP 8: Creating Azure AD Group Logins and Custom Server Roles ==="

    # Define SQL batches for creating Azure AD group logins and server roles
    # This is embedded SQL from 02 Create Server Principles.sql
    $sqlBatches = @(
        @"
-- Create Azure AD Group Logins
use MASTER;

if not exists (select * from sys.server_principals where type = 'X' and name = 'SoftwareEngineering')
begin
    create login SoftwareEngineering from external provider with DEFAULT_DATABASE = [Master];
end;

if not exists (select * from sys.server_principals where type = 'X' and name = 'ProductInnovation')
begin
    create login ProductInnovation from external provider with DEFAULT_DATABASE = [Master];
end;

if not exists (select * from sys.server_principals where type = 'X' and name = 'ProductExcellence')
begin
    create login ProductExcellence from external provider with DEFAULT_DATABASE = [Master];
end;

if not exists (select * from sys.server_principals where type = 'X' and name = 'DataSystems')
begin
    create login DataSystems from external provider with DEFAULT_DATABASE = [Master];
end;

if not exists (select * from sys.server_principals where type = 'X' and name = 'SQLAdmins-Dev')
begin
    create login [SQLAdmins-Dev] from external provider with DEFAULT_DATABASE = [Master];
end;

ALTER SERVER ROLE [sysadmin] ADD MEMBER [SQLAdmins-Dev];

if not exists (select * from sys.server_principals where type = 'X' and name = 'KMS Web Developers')
begin
    create login [KMS Web Developers] from external provider with DEFAULT_DATABASE = [master];
end;
"@,
        @"
-- Create Custom Server Role
if not exists (select * from sys.server_principals where type = 'R' and name = 'EWN')
begin
    create server role EWN authorization Yoda;
end;

grant view any definition to EWN;
grant view server state to EWN;
GRANT ALTER ANY EVENT SESSION TO EWN;

alter server role EWN add member SoftwareEngineering;
alter server role EWN add member ProductInnovation;
alter server role EWN add member DataSystems;
alter server role EWN add member ProductExcellence;
"@,
        @"
-- Grant Database Permissions - DataWarehouse
use DataWarehouse;
alter role db_owner add member SoftwareEngineering;
alter role db_owner add member DataSystems;
alter role db_owner add member ProductInnovation;
alter role db_owner add member ProductExcellence;
GRANT SHOWPLAN TO SoftwareEngineering;
GRANT SHOWPLAN TO DataSystems;
GRANT SHOWPLAN TO ProductInnovation;
GRANT SHOWPLAN TO ProductExcellence;
"@,
        @"
-- Grant Database Permissions - EWN
use EWN;
alter role db_owner add member SoftwareEngineering;
alter role db_owner add member DataSystems;
alter role db_owner add member ProductInnovation;
alter role db_owner add member ProductExcellence;
GRANT SHOWPLAN TO SoftwareEngineering;
GRANT SHOWPLAN TO DataSystems;
GRANT SHOWPLAN TO ProductInnovation;
GRANT SHOWPLAN TO ProductExcellence;
"@,
        @"
-- Grant Database Permissions - Rustici
use Rustici;
alter role db_owner add member SoftwareEngineering;
alter role db_owner add member DataSystems;
alter role db_owner add member ProductInnovation;
alter role db_owner add member ProductExcellence;
GRANT SHOWPLAN TO SoftwareEngineering;
GRANT SHOWPLAN TO DataSystems;
GRANT SHOWPLAN TO ProductInnovation;
GRANT SHOWPLAN TO ProductExcellence;
"@,
        @"
-- Grant Database Permissions - Quartz
use Quartz;
alter role db_owner add member SoftwareEngineering;
alter role db_owner add member DataSystems;
alter role db_owner add member ProductInnovation;
alter role db_owner add member ProductExcellence;
GRANT SHOWPLAN TO SoftwareEngineering;
GRANT SHOWPLAN TO DataSystems;
GRANT SHOWPLAN TO ProductInnovation;
GRANT SHOWPLAN TO ProductExcellence;
"@
    )

    # Execute each SQL batch
    $batchNumber = 0
    $successCount = 0
    $failCount = 0

    foreach ($batch in $sqlBatches) {
        $batchNumber++
        Write-Log "Executing Azure AD group setup batch $batchNumber..."

        $batchResult = sqlcmd -S localhost -U Yoda -P "$SqlPassword" -Q "$batch" -b -t 60 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "  Batch $batchNumber executed successfully"
            $successCount++
        } else {
            Write-Log "  WARNING: Batch $batchNumber had issues: $batchResult" "WARNING"
            $failCount++
        }
    }

    Write-Log "Azure AD group setup complete: $successCount successful, $failCount warnings"

    # Verify SQLAdmins-Dev was created
    $verifyAdmins = sqlcmd -S localhost -U Yoda -P "$SqlPassword" -Q "SELECT name, type_desc FROM sys.server_principals WHERE name = 'SQLAdmins-Dev'" -b -t 30 2>&1
    if ($LASTEXITCODE -eq 0 -and $verifyAdmins -like "*SQLAdmins-Dev*") {
        Write-Log "SUCCESS: SQLAdmins-Dev Azure AD group login created successfully"
    } else {
        Write-Log "WARNING: SQLAdmins-Dev login may not have been created" "WARNING"
    }

    Write-Log "=== SQL Server VM Configuration Completed Successfully ==="

} catch {
    Write-Log "Script execution failed: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}