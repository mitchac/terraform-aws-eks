provider "aws" {
  region = "us-east-1"
  shared_credentials_file = "/home/mitchac/.aws/credentials"
  profile                 = "cmr"
}

locals {
  name            = "complete-${random_string.suffix.result}"
  cluster_version = "1.20"
  region          = "us-east-1"
}

################################################################################
# EKS Module
################################################################################

module "eks" {
  source = "../.."

  cluster_name    = local.name
  cluster_version = local.cluster_version

  vpc_id          = module.vpc.vpc_id
  subnets         = [module.vpc.private_subnets[0], module.vpc.public_subnets[1]]
  fargate_subnets = [module.vpc.private_subnets[2]]

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  # Managed Node Groups
  node_groups_defaults = {
    ami_type  = "AL2_x86_64"
    disk_size = 50
  }

  node_groups = {
    example = {
      desired_capacity = 1
      max_capacity     = 10
      min_capacity     = 1

      instance_types = ["t3.large"]
      capacity_type  = "SPOT"
      subnets = module.vpc.public_subnets
      k8s_labels = {
        Environment = "test"
        GithubRepo  = "terraform-aws-eks"
        GithubOrg   = "terraform-aws-modules"
      }
      additional_tags = {
        ExtraTag = "example"
      }
#      taints = [
#        {
#          key    = "dedicated"
#          value  = "gpuGroup"
#          effect = "NO_SCHEDULE"
#        }
#      ]
      update_config = {
        max_unavailable_percentage = 50 # or set `max_unavailable`
      }
    }
  }

  # AWS Auth (kubernetes_config_map)
#  map_roles = [
#    {
#      rolearn  = "arn:aws:iam::66666666666:role/role1"
#      username = "role1"
#      groups   = ["system:masters"]
#    },
#  ]

  map_users = [
    {
      userarn  = "arn:aws:iam::401305384268:user/MitchCunningham"
      username = "MitchCunningham"
      groups   = ["system:masters"]
    },
    {
      userarn  = "arn:aws:iam::401305384268:user/ben"
      username = "ben"
      groups   = ["system:masters"]
    },
  ]

  map_accounts = [
    "401305384268",
  ]

  tags = {
    Example    = local.name
    GithubRepo = "terraform-aws-eks"
    GithubOrg  = "terraform-aws-modules"
  }
}

################################################################################
# Kubernetes provider configuration
################################################################################

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

################################################################################
# Supporting resources
################################################################################

data "aws_availability_zones" "available" {
  all_availability_zones = true
  filter {
    name   = "zone-name"
    values = ["us-east-1a","us-east-1b"]
  }
}


resource "random_string" "suffix" {
  length  = 8
  special = false
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name                 = local.name
  cidr                 = "10.0.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/elb"              = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/internal-elb"     = "1"
  }

  tags = {
    Example    = local.name
    GithubRepo = "terraform-aws-eks"
    GithubOrg  = "terraform-aws-modules"
  }
}
