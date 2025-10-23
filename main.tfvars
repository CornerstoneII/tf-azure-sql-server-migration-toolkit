# Subscription Configuration
primary_subscription_id = "" # SQL Server resources
vnet_subscription_id    = "" # VNet location

# VM Configuration
win_vm_name    = "vm-usaw02-a22"
location       = "westus2"
admin_username = "ewnadmin"
sql_edition    = "sqldev-gen2" # Options: sqldev-gen2, standard-gen2, enterprise-gen2

# Network Configuration
existing_vnet_name   = "vnet-nonprod-external-devtest"
existing_subnet_name = "snet-beta-web"
existing_vnet_rg     = "nonprod-network"

# Passwords
admin_password = "7FaGIjFMtnLb"
sql_rg         = "sql-pkr-img"
sql_password   = "SGgFlM4Mz?;("

# Azure AD / Entra ID Configuration
# sql_admin_entra_object_id   = ""  # Replace with actual Object ID
# sql_admin_entra_login       = ""                  # Replace with actual admin login
# developers_group_object_id  = ""  # Replace with developers group Object ID
