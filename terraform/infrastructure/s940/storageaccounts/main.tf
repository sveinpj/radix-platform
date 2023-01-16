terraform {
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}

locals {

}
# rule_mapping = {
#   backup_location = "azure_backup_vault_${var.storage_accounts.location}"
# }

##########################################################################################
# Variables

variable "storage_accounts" {
  type = map(object({
    name                              = string                          # Mandatory
    rg_name                           = string                          # Mandatory
    location                          = optional(string, "northeurope") # Optional
    kind                              = optional(string, "StorageV2")   # Optional
    repl                              = optional(string, "LRS")         # Optional
    tier                              = optional(string, "Standard")    # Optional
    backup_center                     = optional(bool, false)           # Optional      
    life_cycle                        = optional(bool, false)
    firewall                          = optional(bool, false)
    ip_rule                           = optional(list(string), ["143.97.110.1"])
    container_delete_retention_policy = optional(bool, true)
    tags                              = optional(map(string), {})
    allow_nested_items_to_be_public   = optional(bool, false) #GUI: Configuration | Allow Blob public access
    shared_access_key_enabled         = optional(bool, true)
    cross_tenant_replication_enabled  = optional(bool, true)
    delete_retention_policy           = optional(bool, true)
    versioning_enabled                = optional(bool, true)
    change_feed_enabled               = optional(bool, true)
  }))
  default = {}
}

variable "vnets" {
  type = map(object({
    vnet_name   = string
    rg_name     = optional(string, "clusters")
    subnet_name = string
  }))
  default = {
    "vnet-c2-prod-34" = {
      vnet_name   = "vnet-c2-prod-34"
      subnet_name = "subnet-c2-prod-34"
      rg_name     = "clusters-westeurope"
    }
    "vnet-eu-34" = {
      vnet_name   = "vnet-eu-34"
      subnet_name = "subnet-eu-34"
    }
  }
}

##########################################################################################
# Virtual Network
data "azurerm_virtual_network" "vnets" {
  for_each            = var.vnets
  name                = each.value["vnet_name"]
  resource_group_name = each.value["rg_name"]
}

data "azurerm_subnet" "subnets" {
  for_each             = var.vnets
  name                 = each.value["subnet_name"]
  resource_group_name  = each.value["rg_name"]
  virtual_network_name = each.value["vnet_name"]
}


resource "azurerm_storage_account" "storageaccounts" {
  for_each                         = var.storage_accounts
  name                             = each.value["name"]
  resource_group_name              = each.value["rg_name"]
  location                         = each.value["location"]
  account_kind                     = each.value["kind"]
  account_replication_type         = each.value["repl"]
  account_tier                     = each.value["tier"]
  allow_nested_items_to_be_public  = each.value["allow_nested_items_to_be_public"]
  cross_tenant_replication_enabled = each.value["cross_tenant_replication_enabled"]
  shared_access_key_enabled        = each.value["shared_access_key_enabled"]
  tags                             = each.value["tags"]

  dynamic "blob_properties" {
    for_each = each.value["kind"] == "*Storage" ? [1] : [0]

    content {
      change_feed_enabled = each.value["change_feed_enabled"]
      versioning_enabled  = each.value["versioning_enabled"]

      dynamic "container_delete_retention_policy" {
        for_each = each.value["container_delete_retention_policy"] == true ? [30] : []
        content {
          days = container_delete_retention_policy.value
        }
      }

      dynamic "delete_retention_policy" {
        for_each = each.value["delete_retention_policy"] == true ? [35] : []

        content {
          days = delete_retention_policy.value
        }
      }
      dynamic "restore_policy" {
        for_each = each.value["backup_center"] == true ? [30] : []
        content {
          days = restore_policy.value
        }
      }
    }
  }
}

##########################################################################################
# Network rules

resource "azurerm_storage_account_network_rules" "network_rule" {
  for_each                   = { for key in compact([for key, value in var.storage_accounts : value.firewall ? key : ""]) : key => var.storage_accounts[key] }
  storage_account_id         = azurerm_storage_account.storageaccounts[each.key].id
  default_action             = "Deny"
  ip_rules                   = each.value["ip_rule"]
  virtual_network_subnet_ids = values(data.azurerm_subnet.subnets)[*].id
  bypass                     = ["AzureServices"]
}

##########################################################################################
# Role assignment
resource "azurerm_role_assignment" "northeurope" {
  #for_each             = { for key in compact([for key, value in var.storage_accounts : value.backup_center ? key : false && value.location == "northeurope" ? key : false && value.kind == "StorageV2" ? key : ""]) : key => var.storage_accounts[key] }
  for_each             = { for key in compact([for key, value in var.storage_accounts : value.backup_center == true  && value.location == "northeurope" && value.kind == "StorageV2" ? key : ""]) : key => var.storage_accounts[key] }
  scope                = azurerm_storage_account.storageaccounts[each.key].id
  role_definition_name = "Storage Account Backup Contributor"
  principal_id         = azurerm_data_protection_backup_vault.northeurope.identity[0].principal_id
  depends_on           = [azurerm_storage_account.storageaccounts]
}

resource "azurerm_role_assignment" "westeurope" {
  #for_each             = { for key in compact([for key, value in var.storage_accounts : value.backup_center ? key : false && value.location == "westeurope" ? key : false && value.kind == "StorageV2" ? key : ""]) : key => var.storage_accounts[key] }
  for_each             = { for key in compact([for key, value in var.storage_accounts : value.backup_center == true  && value.location == "westeurope" && value.kind == "StorageV2" ? key : ""]) : key => var.storage_accounts[key] }
  scope                = azurerm_storage_account.storageaccounts[each.key].id
  role_definition_name = "Storage Account Backup Contributor"
  principal_id         = azurerm_data_protection_backup_vault.westeurope.identity[0].principal_id
  depends_on           = [azurerm_storage_account.storageaccounts]
}

##########################################################################################
# Blob Protection

resource "azurerm_data_protection_backup_instance_blob_storage" "northeurope" {
  #for_each           = { for key in compact([for key, value in var.storage_accounts : value.backup_center ? key : false && value.location == "northeurope" ? key : false && value.kind == "StorageV2" ? key : ""]) : key => var.storage_accounts[key] }
  for_each           = { for key in compact([for key, value in var.storage_accounts : value.backup_center == true && value.location == "northeurope" ? key : ""]) : key => var.storage_accounts[key] }
  name               = each.value.name
  vault_id           = azurerm_data_protection_backup_vault.northeurope.id
  location           = each.value.location
  storage_account_id = azurerm_storage_account.storageaccounts[each.key].id
  backup_policy_id   = azurerm_data_protection_backup_policy_blob_storage.northeurope.id
  depends_on         = [azurerm_role_assignment.northeurope]
}

resource "azurerm_data_protection_backup_instance_blob_storage" "westeurope" {
  #for_each           = { for key in compact([for key, value in var.storage_accounts : value.backup_center ? key : false && value.location == "westeurope" ? key : false && value.kind == "StorageV2" ? key : ""]) : key => var.storage_accounts[key] }
  for_each           = { for key in compact([for key, value in var.storage_accounts : value.backup_center == true && value.location == "westeurope" ? key : ""]) : key => var.storage_accounts[key] }
  name               = each.value.name
  vault_id           = azurerm_data_protection_backup_vault.westeurope.id
  location           = each.value.location
  storage_account_id = azurerm_storage_account.storageaccounts[each.key].id
  backup_policy_id   = azurerm_data_protection_backup_policy_blob_storage.westeurope.id
  depends_on         = [azurerm_role_assignment.westeurope]
}

###########################################################################################
# Management Policy

resource "azurerm_storage_management_policy" "sapolicy" {
  for_each           = { for key in compact([for key, value in var.storage_accounts : value.life_cycle ? key : ""]) : key => var.storage_accounts[key] }
  storage_account_id = azurerm_storage_account.storageaccounts[each.key].id

  rule {
    name    = "Lifecycle-dev"
    enabled = true
    filters {
      blob_types = ["blockBlob"]
    }
    actions {
      version {
        delete_after_days_since_creation = 60
      }
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = 30
        delete_after_days_since_modification_greater_than       = 90
      }
    }
  }
}

##########################################################################################
# Protection Vault

resource "azurerm_data_protection_backup_vault" "northeurope" {
  name                = "s940-azure-backup-vault-northeurope"
  resource_group_name = "backups"
  location            = "northeurope"
  datastore_type      = "VaultStore"
  redundancy          = "LocallyRedundant"
  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_data_protection_backup_vault" "westeurope" {
  name                = "s940-azure-backup-vault-westeurope"
  resource_group_name = "backups"
  location            = "westeurope"
  datastore_type      = "VaultStore"
  redundancy          = "LocallyRedundant"
  identity {
    type = "SystemAssigned"
  }
}

##########################################################################################
# Protection Backup Policy

resource "azurerm_data_protection_backup_policy_blob_storage" "northeurope" {
  name               = "s940-azure-blob-backuppolicy-northeurope"
  vault_id           = azurerm_data_protection_backup_vault.northeurope.id
  retention_duration = "P30D"
}

resource "azurerm_data_protection_backup_policy_blob_storage" "westeurope" {
  name               = "s940-azure-blob-backuppolicy-westeurope"
  vault_id           = azurerm_data_protection_backup_vault.westeurope.id
  retention_duration = "P30D"
}