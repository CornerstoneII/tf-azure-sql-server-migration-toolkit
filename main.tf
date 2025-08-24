# Configure Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.37.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9.1"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "52f9cc50-7e1e-4e82-b8c3-da2757e84a48"
}

# Variables for SQL VM
variable "win_vm_name" {
  type    = string
  default = ""
}

variable "location" {
  type    = string
  default = ""
}

variable "admin_username" {
  type    = string
  default = ""
}

variable "admin_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "sql_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "sql_edition" {
  default = ""
}

variable "existing_vnet_name" {
  default = "vnet-nonprod-external-devtest"
}

variable "existing_subnet_name" {
  default = "snet-beta-web"
}

variable "existing_vnet_rg" {
  default = "" # Resource group for VNet
}

variable "sql_rg" {
  default = "" # Resource group for SQL resources
}

# Variables for BETA01
variable "beta01_vm_name" {
  type    = string
  default = "BETA01"
}

variable "beta01_rg" {
  type    = string
  default = "NONPROD-DEVTEST-NEWBETA"
}

variable "mount_drive_letter" {
  type        = string
  default     = "Z"
  description = "Drive letter to mount the Azure File Share on BETA01 (without colon)"
}

# Generate random password if not provided
resource "random_password" "sql_password" {
  count            = var.admin_password == "" ? 1 : 0
  length           = 20
  special          = true
  override_special = "!@#$%^&*()-_=+[]{}<>:?"
}

locals {
  admin_password = var.admin_password != "" ? var.admin_password : one(random_password.sql_password[*].result)
}

# Get existing VNet and subnet
data "azurerm_virtual_network" "main" {
  name                = var.existing_vnet_name
  resource_group_name = var.existing_vnet_rg
}

data "azurerm_subnet" "main" {
  name                 = var.existing_subnet_name
  virtual_network_name = data.azurerm_virtual_network.main.name
  resource_group_name  = var.existing_vnet_rg
}

# Reference the existing BETA01 VM
data "azurerm_virtual_machine" "beta01" {
  name                = var.beta01_vm_name
  resource_group_name = var.beta01_rg
}

# Create network interface for SQL VM without public IP
resource "azurerm_network_interface" "win" {
  name                = "nic-demo-win"
  location            = var.location
  resource_group_name = var.sql_rg

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Create WIN Server VM
resource "azurerm_windows_virtual_machine" "win" {
  name                = var.win_vm_name
  resource_group_name = var.sql_rg
  location            = var.location
  size                = "Standard_B4ms"
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  network_interface_ids = [
    azurerm_network_interface.win.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 127
  }

  source_image_reference {
    publisher = "microsoftsqlserver"
    offer     = "sql2022-ws2022"
    sku       = var.sql_edition
    version   = "latest"
  }
}

# Configure data disk for SQL
resource "azurerm_managed_disk" "data" {
  name                 = "${var.win_vm_name}-data-disk"
  location             = var.location
  resource_group_name  = var.sql_rg
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = 64
}

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  managed_disk_id    = azurerm_managed_disk.data.id
  virtual_machine_id = azurerm_windows_virtual_machine.win.id
  lun                = 0
  caching            = "ReadOnly"
}

# Configure temp disk for SQL
resource "azurerm_managed_disk" "temp" {
  name                 = "${var.win_vm_name}-temp-disk"
  location             = var.location
  resource_group_name  = var.sql_rg
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = 32
}

resource "azurerm_virtual_machine_data_disk_attachment" "temp" {
  managed_disk_id    = azurerm_managed_disk.temp.id
  virtual_machine_id = azurerm_windows_virtual_machine.win.id
  lun                = 1
  caching            = "ReadOnly"
}

# SQL IaaS Agent Extension with Storage Configuration
resource "azurerm_mssql_virtual_machine" "sql_extension" {
  virtual_machine_id               = azurerm_windows_virtual_machine.win.id
  sql_license_type                 = "PAYG"
  sql_connectivity_port            = 1433
  sql_connectivity_type            = "PRIVATE"
  sql_connectivity_update_username = "Yoda"
  sql_connectivity_update_password = var.sql_password

  # Configure storage settings
  storage_configuration {
    disk_type             = "NEW"
    storage_workload_type = "GENERAL"

    data_settings {
      default_file_path = "F:\\Databases\\UserDBs"
      luns              = [0] # LUN for data disk
    }

    log_settings {
      default_file_path = "F:\\Databases\\UserDBs"
      luns              = [0] # LUN for data disk
    }

    temp_db_settings {
      default_file_path = "H:\\tempDb"
      luns              = [1] # LUN for temp disk
    }
  }

  depends_on = [
    azurerm_virtual_machine_data_disk_attachment.data,
    azurerm_virtual_machine_data_disk_attachment.temp
  ]
}

# Storage Account for Backups
resource "azurerm_storage_account" "backup" {
  name                     = "sqldbbkup0003"
  resource_group_name      = var.sql_rg
  location                 = var.location
  account_tier             = "Standard"
  account_kind             = "StorageV2"
  account_replication_type = "LRS"

  allow_nested_items_to_be_public = false

  depends_on = [
    azurerm_windows_virtual_machine.win
  ]
}

# File Share for Backups
resource "azurerm_storage_share" "backupshare" {
  name                 = "sqldbbkupfs0003"
  storage_account_name = azurerm_storage_account.backup.name
  quota                = 1 # in GB
  depends_on = [
    azurerm_windows_virtual_machine.win,
    azurerm_storage_account.backup
  ]
}

# Create SQLBACKUPS directory in the file share
resource "azurerm_storage_share_directory" "sqlbackups" {
  name             = "SQLBACKUPS"
  storage_share_id = azurerm_storage_share.backupshare.id
  depends_on = [
    azurerm_storage_share.backupshare
  ]
}

# Create a storage container for scripts
resource "azurerm_storage_container" "scripts" {
  name                  = "scripts"
  storage_account_name  = azurerm_storage_account.backup.name
  container_access_type = "private"
}

# Add time delay resource to ensure storage account is ready
resource "time_sleep" "wait_for_storage" {
  depends_on = [
    azurerm_storage_account.backup,
    azurerm_storage_share.backupshare,
    azurerm_storage_share_directory.sqlbackups
  ]

  create_duration = "90s"
}

# Upload SQL script to storage with templatefile processing
resource "azurerm_storage_blob" "sql_script" {
  name                   = "sql-setup-v2.ps1"
  storage_account_name   = azurerm_storage_account.backup.name
  storage_container_name = azurerm_storage_container.scripts.name
  type                   = "Block"
  source = "${path.module}/sql-setup.ps1"
  content_md5 = filemd5("${path.module}/sql-setup.ps1")

  depends_on = [
    azurerm_storage_account.backup,
    azurerm_storage_share.backupshare,
    azurerm_storage_container.scripts,
    time_sleep.wait_for_storage
  ]
}

# Upload BETA01 script to storage with templatefile processing
resource "azurerm_storage_blob" "beta01_script" {
  name                   = "beta01-setup.ps1"
  storage_account_name   = azurerm_storage_account.backup.name
  storage_container_name = azurerm_storage_container.scripts.name
  type                   = "Block"
  source = "${path.module}/beta01-setup.ps1"

  depends_on = [
    azurerm_storage_account.backup,
    azurerm_storage_share.backupshare,
    azurerm_storage_container.scripts,
    time_sleep.wait_for_storage
  ]
}

# SQL Server VM Extension - Download and execute script with improved error handling
resource "azurerm_virtual_machine_extension" "sql_combined" {
  name                 = "sql-combined-setup"
  virtual_machine_id   = azurerm_windows_virtual_machine.win.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    fileUris = ["https://${azurerm_storage_account.backup.name}.blob.core.windows.net/${azurerm_storage_container.scripts.name}/${azurerm_storage_blob.sql_script.name}"]
  })

  protected_settings = jsonencode({
    storageAccountName = azurerm_storage_account.backup.name
    storageAccountKey  = azurerm_storage_account.backup.primary_access_key
    commandToExecute   = "powershell -ExecutionPolicy Unrestricted -File sql-setup-v2.ps1 -StorageAccountName \"${azurerm_storage_account.backup.name}\" -StorageAccountKey \"${azurerm_storage_account.backup.primary_access_key}\" -ShareName \"${azurerm_storage_share.backupshare.name}\" -DriveLetter \"${var.mount_drive_letter}\" -SqlPassword \"${var.sql_password}\""
  })

  depends_on = [
    azurerm_mssql_virtual_machine.sql_extension,
    azurerm_storage_share_directory.sqlbackups,
    azurerm_storage_blob.sql_script,
    time_sleep.wait_for_storage
  ]

  tags = {
    Purpose = "Complete SQL Server Setup - Create dirs, Install SSMS, Mount share, Copy backups"
    Target  = "SQL Server"
  }
}

# BETA01 VM Extension - Download and execute script with improved error handling
resource "azurerm_virtual_machine_extension" "beta01_combined" {
  name                 = "beta01-combined-setup"
  virtual_machine_id   = data.azurerm_virtual_machine.beta01.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    fileUris = ["https://${azurerm_storage_account.backup.name}.blob.core.windows.net/${azurerm_storage_container.scripts.name}/${azurerm_storage_blob.beta01_script.name}"]
  })

  protected_settings = jsonencode({
    storageAccountName = azurerm_storage_account.backup.name
    storageAccountKey  = azurerm_storage_account.backup.primary_access_key
    commandToExecute   = "powershell -ExecutionPolicy Unrestricted -File beta01-setup.ps1 -StorageAccountName \"${azurerm_storage_account.backup.name}\" -StorageAccountKey \"${azurerm_storage_account.backup.primary_access_key}\" -ShareName \"${azurerm_storage_share.backupshare.name}\" -DriveLetter \"${var.mount_drive_letter}\""
  })

  depends_on = [
    azurerm_storage_share_directory.sqlbackups,
    azurerm_storage_blob.beta01_script,
    time_sleep.wait_for_storage
  ]

  tags = {
    Purpose = "Complete BETA01 Setup - Mount share and copy backup files"
    Target  = "BETA01"
  }
}

# ---------------------------
# Outputs
# ---------------------------

# Output the storage key for mounting
output "storage_account_key" {
  value     = azurerm_storage_account.backup.primary_access_key
  sensitive = true
}

# Output important information for SQL VM
output "win_vm_name" {
  value = azurerm_windows_virtual_machine.win.name
}

output "win_private_ip" {
  value = azurerm_network_interface.win.private_ip_address
}

output "sql_admin_username" {
  value = var.admin_username
}

# Output information for BETA01
output "beta01_vm_info" {
  value = {
    vm_name        = data.azurerm_virtual_machine.beta01.name
    resource_group = data.azurerm_virtual_machine.beta01.resource_group_name
    vm_id          = data.azurerm_virtual_machine.beta01.id
  }
}

output "mounted_storage_info" {
  value = {
    storage_account = azurerm_storage_account.backup.name
    file_share      = azurerm_storage_share.backupshare.name
    mount_point     = "${var.mount_drive_letter}:"
    unc_path        = "\\\\${azurerm_storage_account.backup.name}.file.core.windows.net\\${azurerm_storage_share.backupshare.name}"
    quota_gb        = azurerm_storage_share.backupshare.quota
    sqlbackups_path = "${var.mount_drive_letter}:\\SQLBACKUPS"
  }
}

output "manual_mount_command_sql" {
  value       = "net use ${var.mount_drive_letter}: \\\\${azurerm_storage_account.backup.name}.file.core.windows.net\\${azurerm_storage_share.backupshare.name} /persistent:yes /user:AZURE\\${azurerm_storage_account.backup.name} [STORAGE_KEY]"
  description = "Manual command to mount the share on SQL Server if needed"
}

output "manual_mount_command_beta01" {
  value       = "net use ${var.mount_drive_letter}: \\\\${azurerm_storage_account.backup.name}.file.core.windows.net\\${azurerm_storage_share.backupshare.name} /persistent:yes /user:AZURE\\${azurerm_storage_account.backup.name} [STORAGE_KEY]"
  description = "Manual command to mount the share on BETA01 if needed"
}

output "backup_copy_status" {
  value = {
    beta01_source_path   = "F:\\SQLBackups"
    file_share_path      = "${var.mount_drive_letter}:\\SQLBACKUPS"
    sql_server_dest_path = "F:\\SQLBackups"
    copy_sequence        = "BETA01 → File Share → SQL Server"
    expected_files       = "*.bak files from BETA01"
    beta01_vm_name       = data.azurerm_virtual_machine.beta01.name
    extension_names      = "sql-combined-setup, beta01-combined-setup"
  }
  description = "Information about the automated backup file copy process"
}

# Output script log locations for troubleshooting
output "troubleshooting_info" {
  value = {
    sql_server_log   = "C:\\sql-setup.log"
    beta01_log       = "C:\\beta01-setup.log"
    storage_account  = azurerm_storage_account.backup.name
    file_share       = azurerm_storage_share.backupshare.name
    script_container = azurerm_storage_container.scripts.name
    scripts_uploaded = [
      azurerm_storage_blob.sql_script.name,
      azurerm_storage_blob.beta01_script.name
    ]
  }
  description = "Locations of log files and debugging information"
}
