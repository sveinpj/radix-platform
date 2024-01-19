variable "resource_groups" {
  type    = list(string)
  default = ["development"]
}

variable "storageaccounts" {
  description = "Max 15 characters lowercase in the storageaccount name"
  type = map(object({
    name                     = string
    resource_group_name      = optional(string, "s941-development")
    location                 = optional(string, "northeurope")
    account_tier             = optional(string, "Standard")
    account_replication_type = optional(string, "LRS")
    kind                     = optional(string, "StorageV2")
    change_feed_enabled      = optional(bool, false)
    versioning_enabled       = optional(bool, false)
    roleassignment           = optional(map(object({ backup = optional(bool, false) })))
    principal_id             = optional(string)
    private_endpoint         = optional(bool, false)
    firewall                 = optional(bool, true)
  }))
  default = {
    diagnostics = {
      name = "diagnostics"
      roleassignment = {
        "Storage Account Backup Contributor" = {
          backup = true
        }
      }
    }
    terraform = {
      name                     = "terraform"
      account_replication_type = "RAGRS"
      private_endpoint         = true
      roleassignment = {
        "Storage Account Backup Contributor" = {
          backup = true
        }
      }
    }
  }
}