output "data" {
  value = local.outputs
}

output "mi_id" {
  value = module.mi.data.id
}

output "workspace_id" {
  value = module.loganalytics.data.workspace_id
}

output "environment" {
  value = local.outputs.enviroment
}
