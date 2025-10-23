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
    azapi = {
      source  = "azure/azapi"
      version = "~> 1.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = ""
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
  default     = "Y"
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
  name                = "nic-usaw02-tst"
  location            = var.location
  resource_group_name = var.sql_rg

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Create Azure Private DNS Zone for name resolution
resource "azurerm_private_dns_zone" "internal" {
  name                = "ewn.local"
  resource_group_name = var.sql_rg

  tags = {
    Purpose = "DNS resolution for Azure VMs"
  }
}

# Link DNS Zone to VNet for automatic resolution with auto-registration
resource "azurerm_private_dns_zone_virtual_network_link" "vnet_link" {
  name                  = "link-vnet-nonprod-external-devtest"
  resource_group_name   = var.sql_rg
  private_dns_zone_name = azurerm_private_dns_zone.internal.name
  virtual_network_id    = data.azurerm_virtual_network.main.id
  registration_enabled  = true

  tags = {
    Purpose = "Enable DNS resolution for Azure VPN clients with auto-registration"
  }
}

# Create DNS A record for SQL Server VM
resource "azurerm_private_dns_a_record" "sql_vm" {
  name                = "vm-usaw02-a22"
  zone_name           = azurerm_private_dns_zone.internal.name
  resource_group_name = var.sql_rg
  ttl                 = 300
  records             = [azurerm_network_interface.win.private_ip_address]

  tags = {
    Purpose = "DNS resolution for SQL Server VM"
  }
}

# Create User-Assigned Managed Identity for SQL operations
resource "azurerm_user_assigned_identity" "sql_managed_identity" {
  name                = "mi-sql-tst-win"
  resource_group_name = var.sql_rg
  location            = var.location

  tags = {
    Purpose = "Managed identity for SQL Server database operations"
    Project = "SQL-Migration"
  }
}

# Get all directory role templates
# data "azuread_directory_role_templates" "all" {}

# Find the Directory Readers role template
# locals {
#   directory_readers_template = [
#     for template in data.azuread_directory_role_templates.all.role_templates :
#     template if template.display_name == "Directory Readers"
#   ][0]
# }

# Assign Directory Readers role to the managed identity for Azure AD authentication
# NOTE: Commented out due to insufficient privileges error (403)
# Manual assignment required: TJ manually assigned Directory Readers role to mi-sql-tst-win
# resource "azuread_directory_role_assignment" "mi_directory_readers" {
#   role_id             = local.directory_readers_template.object_id
#   principal_object_id = azurerm_user_assigned_identity.sql_managed_identity.principal_id
#
#   depends_on = [
#     azurerm_user_assigned_identity.sql_managed_identity
#   ]
# }

# Get user object IDs for Key Vault access policies
data "azuread_user" "tina_admin" {
  user_principal_name = "tina.weissenburg.admin@ewn.com"
}

data "azuread_user" "taylor_admin" {
  user_principal_name = "taylor.buchanan.admin@ewn.com"
}


# Create Key Vault for storing SQL Server secrets
resource "azurerm_key_vault" "sql_secrets" {
  name                = "kv-sql-tst-win"
  location            = var.location
  resource_group_name = var.sql_rg
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  enable_rbac_authorization  = false
  purge_protection_enabled   = false
  soft_delete_retention_days = 7

  # Give managed identity access to Key Vault secrets
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_user_assigned_identity.sql_managed_identity.principal_id

    secret_permissions = [
      "Get",
      "List"
    ]
  }

  # Give current user/service principal access to manage secrets
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Purge",
      "Recover"
    ]
  }

  # Give Tina Weissenburg admin access to get and list secrets
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azuread_user.tina_admin.object_id

    secret_permissions = [
      "Get",
      "List"
    ]
  }

  # Give Taylor Buchanan admin access to get and list secrets
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azuread_user.taylor_admin.object_id

    secret_permissions = [
      "Get",
      "List"
    ]
  }


  tags = {
    Purpose = "SQL Server secrets storage"
    Project = "SQL-Migration"
  }
}

# Store SQL Server Yoda account password
resource "azurerm_key_vault_secret" "sql_yoda_password" {
  name         = "sql-yoda-password"
  value        = var.sql_password
  key_vault_id = azurerm_key_vault.sql_secrets.id

  depends_on = [
    azurerm_key_vault.sql_secrets
  ]
}

# Store SQL Server admin password
resource "azurerm_key_vault_secret" "sql_admin_password" {
  name         = "sql-admin-password"
  value        = var.admin_password
  key_vault_id = azurerm_key_vault.sql_secrets.id

  depends_on = [
    azurerm_key_vault.sql_secrets
  ]
}

# Store storage account access key
resource "azurerm_key_vault_secret" "storage_account_key" {
  name         = "storage-account-key"
  value        = azurerm_storage_account.backup.primary_access_key
  key_vault_id = azurerm_key_vault.sql_secrets.id

  depends_on = [
    azurerm_key_vault.sql_secrets,
    azurerm_storage_account.backup
  ]
}

# Grant managed identity permissions for storage operations
resource "azurerm_role_assignment" "mi_storage_file_contributor" {
  scope                = azurerm_storage_account.backup.id
  role_definition_name = "Storage File Data SMB Share Contributor"
  principal_id         = azurerm_user_assigned_identity.sql_managed_identity.principal_id
}

resource "azurerm_role_assignment" "mi_storage_blob_reader" {
  scope                = azurerm_storage_account.backup.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.sql_managed_identity.principal_id
}

# Grant managed identity permissions to manage SQL VM Azure AD admin
data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "mi_contributor" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.sql_rg}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.sql_managed_identity.principal_id
}

resource "azurerm_role_assignment" "mi_reader" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.sql_rg}"
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.sql_managed_identity.principal_id
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

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.sql_managed_identity.id]
  }

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
    azurerm_virtual_machine_data_disk_attachment.temp,
    azurerm_role_assignment.mi_storage_file_contributor,
    azurerm_role_assignment.mi_storage_blob_reader,
    azurerm_role_assignment.mi_contributor,
    azurerm_role_assignment.mi_reader
  ]
}

# Enable Azure AD authentication and set managed identity as admin in one step
resource "azapi_update_resource" "sql_vm_aad_admin" {
  type        = "Microsoft.SqlVirtualMachine/sqlVirtualMachines@2022-02-01"
  resource_id = azurerm_mssql_virtual_machine.sql_extension.id

  body = jsonencode({
    properties = {
      azureADAuthenticationSettings = {
        azureADAuthenticationEnabled = true
        msiClientId                  = azurerm_user_assigned_identity.sql_managed_identity.client_id
      }
      sqlServerLicenseType = "PAYG"
      sqlManagement        = "Full"
    }
  })

  depends_on = [
    azurerm_mssql_virtual_machine.sql_extension,
    azurerm_role_assignment.mi_contributor,
    azurerm_role_assignment.mi_reader
  ]
}

# Storage Account for Backups
resource "azurerm_storage_account" "backup" {
  name                     = "sqldbbkup0001"
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
  name               = "sqldbbkupfs0001"
  storage_account_id = azurerm_storage_account.backup.id
  quota              = 1 # in GB
  depends_on = [
    azurerm_windows_virtual_machine.win,
    azurerm_storage_account.backup
  ]
}

# Create SQLBACKUPS directory in the file share
resource "azurerm_storage_share_directory" "sqlbackups" {
  name             = "SQLBACKUPS"
  storage_share_id = "https://${azurerm_storage_account.backup.name}.file.core.windows.net/${azurerm_storage_share.backupshare.name}"
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

# Upload SQL PowerShell setup script to storage
# Note: SQL commands for Azure AD groups are now embedded in the PowerShell script
resource "azurerm_storage_blob" "sql_script" {
  name                   = "sql-setup-fixed.ps1"
  storage_account_name   = azurerm_storage_account.backup.name
  storage_container_name = azurerm_storage_container.scripts.name
  type                   = "Block"
  source                 = "${path.module}/sql-setup-fixed.ps1"
  content_md5            = filemd5("${path.module}/sql-setup-fixed.ps1")

  depends_on = [
    azurerm_storage_account.backup,
    azurerm_storage_share.backupshare,
    azurerm_storage_container.scripts,
    time_sleep.wait_for_storage
  ]
}

# Upload BETA01 script to storage with templatefile processing
resource "azurerm_storage_blob" "beta01_script" {
  name                   = "beta01-setup-direct.ps1"
  storage_account_name   = azurerm_storage_account.backup.name
  storage_container_name = azurerm_storage_container.scripts.name
  type                   = "Block"
  source                 = "${path.module}/beta01-setup-direct.ps1"
  content_md5            = filemd5("${path.module}/beta01-setup-direct.ps1")

  depends_on = [
    azurerm_storage_account.backup,
    azurerm_storage_share.backupshare,
    azurerm_storage_container.scripts,
    time_sleep.wait_for_storage
  ]
}

# SQL Server VM Extension - Download and execute script with improved error handling
resource "azurerm_virtual_machine_extension" "sql_combined" {
  name                 = "sql-usaw02-setup"
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
    commandToExecute   = "powershell -ExecutionPolicy Unrestricted -File sql-setup-fixed.ps1 -StorageAccountName \"${azurerm_storage_account.backup.name}\" -StorageAccountKey \"${azurerm_storage_account.backup.primary_access_key}\" -ShareName \"${azurerm_storage_share.backupshare.name}\" -DriveLetter \"${var.mount_drive_letter}\" -SqlPassword \"${var.sql_password}\""
  })

  depends_on = [
    azurerm_mssql_virtual_machine.sql_extension,
    azapi_update_resource.sql_vm_aad_admin,
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
  name                 = "beta01-usaw02-setup"
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
    commandToExecute   = "powershell -ExecutionPolicy Unrestricted -File beta01-setup-direct.ps1 -StorageAccountName \"${azurerm_storage_account.backup.name}\" -StorageAccountKey \"${azurerm_storage_account.backup.primary_access_key}\" -ShareName \"${azurerm_storage_share.backupshare.name}\" -DriveLetter \"${var.mount_drive_letter}\""
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

# Output Key Vault information
output "key_vault_info" {
  value = {
    name      = azurerm_key_vault.sql_secrets.name
    id        = azurerm_key_vault.sql_secrets.id
    vault_uri = azurerm_key_vault.sql_secrets.vault_uri
    secrets = [
      "sql-yoda-password",
      "sql-admin-password",
      "storage-account-key"
    ]
    authorized_users = [
      "tina.weissenburg.admin@ewn.com",
      "taylor.buchanan.admin@ewn.com"
    ]
    user_permissions = "Get, List secrets"
  }
  description = "Key Vault information and stored secrets"
}

# Output managed identity information
output "managed_identity_info" {
  value = {
    name                  = azurerm_user_assigned_identity.sql_managed_identity.name
    principal_id          = azurerm_user_assigned_identity.sql_managed_identity.principal_id
    client_id             = azurerm_user_assigned_identity.sql_managed_identity.client_id
    tenant_id             = azurerm_user_assigned_identity.sql_managed_identity.tenant_id
    has_directory_readers = true
    key_vault_access      = "Get, List secrets"
  }
  description = "Managed identity details and permissions"
}

# Output DNS information
output "dns_info" {
  value = {
    dns_zone_name     = azurerm_private_dns_zone.internal.name
    auto_registration = "enabled"
    sql_vm_short_name = azurerm_private_dns_a_record.sql_vm.name
    sql_vm_fqdn       = "${azurerm_private_dns_a_record.sql_vm.name}.${azurerm_private_dns_zone.internal.name}"
    sql_vm_ip         = azurerm_network_interface.win.private_ip_address
    connection_options = [
      azurerm_private_dns_a_record.sql_vm.name,
      "${azurerm_private_dns_a_record.sql_vm.name}.${azurerm_private_dns_zone.internal.name}",
      azurerm_network_interface.win.private_ip_address
    ]
    note = "Auto-registration is enabled - VMs automatically register their names in DNS zone"
  }
  description = "DNS configuration - use any connection option in SSMS"
}
