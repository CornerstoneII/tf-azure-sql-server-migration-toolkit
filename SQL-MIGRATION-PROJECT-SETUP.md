# SQL Server Migration Automation Project Setup Guide

## Project Information

**Project Name**: `SQL Server Migration Automation - Azure Terraform`

**Project Description**:

```
Automated SQL Server migration solution using Terraform infrastructure-as-code and PowerShell automation. Features managed identity authentication, Azure AD integration, and automated database restoration from BETA01 to new Azure SQL Server VM.

Key Components:
- Terraform infrastructure deployment (main.tf, variables.tf)
- PowerShell automation scripts (sql-setup-fixed.ps1, beta01-setup-direct.ps1)
- Azure managed identity authentication with REST API integration
- Automated database migration for 5 databases (EWN, DataWarehouse, Quartz, Rustici, TestDB)
- Comprehensive error handling and logging

Status: Production-ready with 95% automation achieved
Architecture: BETA01 VM → Azure File Share → New SQL Server VM
Authentication: Managed identity exclusive with Azure AD integration
```

## Files to Upload to Claude Portal

### 1. Core Infrastructure Files

- `main.tf` - Primary Terraform configuration
- `variables.tf` - Variable definitions
- `main.tfvars` - Environment-specific values

### 2. Automation Scripts

- `sql-setup-fixed.ps1` - Main SQL Server setup and database restoration
- `beta01-setup-direct.ps1` - BETA01 backup file copying

### 3. Documentation

- `Complete-Project-Documentation-Summary.txt` - Comprehensive project overview
- `Azure-AD-Managed-Identity-Implementation-Summary.txt` - Azure AD implementation details
- `PROJECT-CONTEXT.md` - Quick reference for Claude (create this next)

## Project Instructions for Claude

When setting up the project in Claude Portal, include these instructions:

```
This is an Azure SQL Server migration automation project. Key context:

CURRENT STATUS:
- Infrastructure deploys successfully via Terraform
- PowerShell scripts execute and restore databases successfully
- Managed identity authentication working (sqlcmd -G -C)
- Azure Portal shows Microsoft Entra Authentication as "Disabled" despite working auth

CURRENT ISSUE:
- Need to resolve Azure Portal not reflecting enabled Azure AD authentication
- Working on REST API integration in PowerShell script for Azure AD admin config

KEY FILES:
- main.tf: Terraform infrastructure with azapi_update_resource for Azure AD
- sql-setup-fixed.ps1: PowerShell script with managed identity REST API calls
- Complete-Project-Documentation-Summary.txt: Full project history and context

ENVIRONMENT:
- Subscription: 52f9cc50-7e1e-4e82-b8c3-da2757e84a48
- Resource Group: sql-pkr-img
- SQL VM: vm-usaw02-a22
- Managed Identity: mi-sql-tst-win
- Storage: sqldbbkup0001

DEPLOYMENT:
terraform apply -var-file="main.tfvars"

Always check documentation files for full context before making changes.
```

## Next Steps

1. Go to https://claude.ai
2. Click "Create Project"
3. Use the project name and description above
4. Upload the files listed in section "Files to Upload"
5. Add the project instructions
6. Test the project setup by asking Claude about the current Azure AD authentication issue

## Quick Reference Commands

```bash
# Deploy infrastructure
terraform apply -var-file="main.tfvars"

# Force script update
terraform apply -target=azurerm_storage_blob.sql_script -target=azurerm_virtual_machine_extension.sql_combined -var-file="main.tfvars" -replace=azurerm_storage_blob.sql_script -replace=azurerm_virtual_machine_extension.sql_combined

# Check logs on SQL VM
Get-Content "C:\sql-setup.log" -Tail 50
Get-Content "C:\WindowsAzure\Logs\Plugins\Microsoft.Compute.CustomScriptExtension\1.10.20\CustomScriptHandler.log" -Tail 50

# Test managed identity auth
sqlcmd -S localhost -G -Q "SELECT @@VERSION" -C
```
