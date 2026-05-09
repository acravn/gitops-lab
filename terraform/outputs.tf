output "dev_cluster_name" {
  value = module.eks_dev.cluster_name
}

output "qa_cluster_name" {
  value = module.eks_qa.cluster_name
}

output "region" {
  value = var.region
}

output "dev_cluster_endpoint" {
  value = module.eks_dev.cluster_endpoint
}

output "qa_cluster_endpoint" {
  value = module.eks_qa.cluster_endpoint
}
