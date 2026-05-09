terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ── VPC ────────────────────────────────────────────────────────────────────────
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "gitops-lab-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.region}a", "${var.region}b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true  # cost optimization for lab
  enable_dns_hostnames = true

  tags = {
    Environment = "lab"
    ManagedBy   = "terraform"
  }
}

# ── Dev EKS Cluster ────────────────────────────────────────────────────────────
module "eks_dev" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "gitops-lab-dev"
  cluster_version = "1.31"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]  # cost optimized for lab
      min_size       = 2
      max_size       = 3
      desired_size   = 2

      labels = {
        environment = "dev"
      }
    }
  }

  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

# ── QA EKS Cluster ─────────────────────────────────────────────────────────────
module "eks_qa" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "gitops-lab-qa"
  cluster_version = "1.31"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 3
      desired_size   = 2

      labels = {
        environment = "qa"
      }
    }
  }

  tags = {
    Environment = "qa"
    ManagedBy   = "terraform"
  }
}
