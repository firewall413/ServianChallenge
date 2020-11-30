dependency "shared" {
  config_path = "../shared"
}

inputs = {
  aws_zones = dependency.shared.outputs.aws_zones
  db_subnet_group_name = dependency.shared.outputs.db_subnet_group_name
  ecs_cluster_name = dependency.shared.outputs.ecs_cluster_name
  ecsServiceRole_arn = dependency.shared.outputs.ecsServiceRole_arn
  private_subnet_ids = dependency.shared.outputs.private_subnet_ids
  public_subnet_ids = dependency.shared.outputs.public_subnet_ids
  vpc_default_sg_id = dependency.shared.outputs.vpc_default_sg_id
  vpc_id = dependency.shared.outputs.vpc_id
}
