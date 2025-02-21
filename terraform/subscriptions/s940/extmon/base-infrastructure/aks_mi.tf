module "radix_id_akskubelet_mi" {
  source              = "../../../modules/userassignedidentity"
  name                = "radix-id-akskubelet-${module.config.environment}"
  location            = module.config.location
  resource_group_name = module.resourcegroup_common.data.name
  # roleassignments = {
  #   arcpull = {
  #     role     = "AcrPull"
  #     scope_id = module.acr.azurerm_container_registry_id
  #   }
  #   arccache = {
  #     role     = "AcrPull"
  #     scope_id = module.acr.azurerm_container_registry_cache_id
  #   }
  # }
}

module "radix_id_aks_mi" {
  source              = "../../../modules/userassignedidentity"
  name                = "radix-id-aks-${module.config.environment}"
  location            = module.config.location
  resource_group_name = module.resourcegroup_common.data.name
  roleassignments = {
    mi_operator = {
      role     = "Managed Identity Operator"
      scope_id = module.radix_id_akskubelet_mi.data.id
    }
    rg_contributor = {
      role     = "Contributor"
      scope_id = data.azurerm_resource_group.monitoring.id
    }
    rg_common_zone = {
      role     = "Contributor"
      scope_id = module.resourcegroup_common.data.id
    }
  }
}