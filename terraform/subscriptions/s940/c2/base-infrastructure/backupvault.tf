module "backupvault" {
  source                = "../../../modules/backupvaults"
  name                  = "Backupvault-${module.config.environment}"
  resource_group_name   = module.resourcegroup_common.data.name
  location              = module.config.location
  policyblobstoragename = "Backuppolicy-blob"
}