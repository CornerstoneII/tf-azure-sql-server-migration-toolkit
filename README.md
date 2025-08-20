# azure-sql-server-migration-toolkit

**Automated SQL Server deployment and database migration toolkit using Terraform and Azure services**

## Overview

This repository provides a complete Infrastructure as Code (IaC) solution for deploying SQL Server 2022 on Azure Windows VMs with automated database backup migration from existing servers. The toolkit uses Terraform to orchestrate VM provisioning, Azure File Share configuration, and PowerShell scripts for seamless database backup transfers.

## Repository Name

`azure-sql-server-migration-toolkit`

## Features

- ✅ **Automated SQL Server 2022 VM Deployment** - Complete Windows Server 2022 with SQL Server 2022
- ✅ **Azure File Share Integration** - Centralized backup storage with persistent mounting
- ✅ **Database Backup Migration** - Automated transfer from source VMs to new SQL Server
- ✅ **SSMS Installation** - Automatic SQL Server Management Studio deployment
- ✅ **Storage Configuration** - Optimized data and temp disk setup for SQL workloads
- ✅ **Network Security** - Private networking with no public IP exposure
- ✅ **Comprehensive Logging** - Detailed execution logs for troubleshooting
- ✅ **Retry Logic** - Robust error handling and automatic retry mechanisms

## Architecture

```
┌─────────────┐    ┌─────────────────┐    ┌──────────────────┐
│   BETA01    │───▶│  Azure File     │───▶│   New SQL        │
│  (Source)   │    │     Share       │    │   Server         │
│             │    │                 │    │                  │
│ F:\SQLBackups│    │ Z:\SQLBACKUPS   │    │ F:\SQLBackups    │
└─────────────┘    └─────────────────┘    │ Z:\(mounted)     │
                                          └──────────────────┘
```

**Data Flow:**

1. BETA01 → Azure File Share (temporary transfer)
2. Azure File Share → New SQL Server (persistent storage)
3. File Share remains mounted for future operations

## Prerequisites

- **Terraform** >= 1.0
- **Azure CLI** with authenticated session
- **PowerShell** execution policy set to allow scripts
- **Azure Subscription** with appropriate permissions
- **Existing VNET** and subnet in Azure
- **Source VM** (BETA01) with backup files in `F:\SQLBackups`

## Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/your-org/azure-sql-server-migration-toolkit.git
cd azure-sql-server-migration-toolkit
```

### 2. Configure Variables

Create a `terraform.tfvars` file:

```hcl
# Required Variables
win_vm_name          = "SQL-SERVER-01"
location             = "East US"
admin_username       = "sqladmin"
admin_password       = "YourSecurePassword123!"
sql_password         = "YourSQLPassword123!"
sql_edition          = "sqldev-gen2"
existing_vnet_rg     = "your-vnet-resource-group"
sql_rg              = "your-sql-resource-group"

# Optional Variables
mount_drive_letter   = "Z"
beta01_vm_name      = "BETA01"
beta01_rg           = "NONPROD-DEVTEST-NEWBETA"
```

### 3. Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

### 4. Monitor Deployment

Check script execution logs:

```powershell
# On SQL Server VM
Get-Content C:\sql-setup.log -Tail 50

# On BETA01 VM
Get-Content C:\beta01-setup.log -Tail 50
```

## File Structure

```
azure-sql-server-migration-toolkit/
├── main.tf                 # Main Terraform configuration
├── sql-setup.ps1          # SQL Server VM setup script
├── beta01-setup.ps1       # Source VM backup copy script
├── terraform.tfvars.example
├── variables.tf           # Variable definitions
├── outputs.tf            # Output values
└── README.md             # This file
```

## Key Components

### Terraform Configuration (`main.tf`)

- **VM Provisioning** - Windows Server 2022 with SQL Server 2022
- **Storage Setup** - Data and temp disks for SQL optimization
- **Network Configuration** - Private IP, security groups
- **Azure File Share** - Centralized backup storage
- **VM Extensions** - PowerShell script execution

### SQL Server Setup Script (`sql-setup.ps1`)

- **Directory Creation** - Local backup directories
- **SSMS Installation** - SQL Server Management Studio
- **Azure File Share Mounting** - Persistent drive mapping
- **Backup File Transfer** - Smart waiting and retry logic
- **Comprehensive Logging** - Detailed execution tracking

### BETA01 Setup Script (`beta01-setup.ps1`)

- **Source Backup Detection** - Automatic discovery of .bak files
- **Azure File Share Upload** - Transfer to centralized storage
- **Network Validation** - Connectivity and authentication testing
- **Error Handling** - Robust retry mechanisms

## Configuration Options

### VM Sizing

```hcl
# Standard_B4ms (4 vCPUs, 16GB RAM) - Default
# Upgrade options:
# Standard_D4s_v3 (4 vCPUs, 16GB RAM, Premium SSD)
# Standard_E4s_v3 (4 vCPUs, 32GB RAM, Memory optimized)
```

### SQL Server Editions

```hcl
sql_edition = "sqldev-gen2"      # Developer Edition (Free)
sql_edition = "standard-gen2"    # Standard Edition
sql_edition = "enterprise-gen2"  # Enterprise Edition
```

### Storage Configuration

```hcl
# Data Disk (F:) - 32GB StandardSSD_LRS
# Temp Disk (H:) - 32GB StandardSSD_LRS
# OS Disk (C:)   - 127GB Premium_LRS
```

## Monitoring and Troubleshooting

### Check Deployment Status

```bash
# View Terraform outputs
terraform output

# Get storage account key
terraform output -raw storage_account_key
```

### Manual File Share Mounting

```powershell
# SQL Server - Manual mount command
net use Z: \\sqldbbkup0003.file.core.windows.net\sqldbbkupfs0003 /persistent:yes /user:AZURE\sqldbbkup0003 [STORAGE_KEY]

# Verify mount
Test-Path Z:\SQLBACKUPS
Get-ChildItem Z:\SQLBACKUPS -Filter "*.bak"
```

### Common Issues

**Issue: Port 445 Blocked**

```
Solution: Configure corporate firewall or use Azure VPN Gateway
```

**Issue: Authentication Failed**

```
Solution: Verify storage account key and credential format
Check: terraform output storage_account_key
```

**Issue: Files Not Copied**

```
Solution: Check timing - SQL Server may check before BETA01 completes
Manual fix: Run copy script manually on SQL Server
```

## Security Considerations

- **No Public IPs** - All VMs use private networking only
- **Storage Account Keys** - Secured in Terraform state and VM extensions
- **Network Isolation** - Resources deployed in existing VNETs
- **Credential Management** - Sensitive variables marked appropriately

## Outputs

After successful deployment:

```hcl
win_vm_name           = "SQL-SERVER-01"
win_private_ip        = "10.25.30.6"
storage_account       = "sqldbbkup0003"
file_share           = "sqldbbkupfs0003"
mount_point          = "Z:"
sql_admin_username   = "sqladmin"
```

## Cleanup

```bash
# Destroy all resources
terraform destroy

# Confirm when prompted
yes
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/improvement`)
3. Commit changes (`git commit -am 'Add new feature'`)
4. Push to branch (`git push origin feature/improvement`)
5. Create Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For issues and questions:

- Create an [Issue](https://github.com/your-org/azure-sql-server-migration-toolkit/issues)
- Check existing [Discussions](https://github.com/your-org/azure-sql-server-migration-toolkit/discussions)
- Review [Wiki](https://github.com/your-org/azure-sql-server-migration-toolkit/wiki) for detailed guides

## Changelog

### v1.0.0 (Current)

- Initial release with automated SQL Server deployment
- Azure File Share integration for backup migration
- Comprehensive PowerShell automation scripts
- Smart retry logic and error handling
- Complete Terraform IaC implementation

---

**Built with ❤️ for Azure SQL Server migrations**
