variable "name" {
  description = "Short name used for resources created by this routing-peer site."
  type        = string

  validation {
    condition = (
      can(regex("^[a-z](?:[a-z0-9-]{0,18}[a-z0-9])?$", var.name)) &&
      !startswith(var.name, "internal-")
    )
    error_message = "name must be 1-20 lowercase letters, numbers, or internal hyphens; start with a letter; and not start with internal-."
  }
}

variable "vpc_id" {
  description = "ID of the existing VPC in which to deploy the routing peers."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be an AWS VPC ID."
  }
}

variable "subnet_ids" {
  description = "Subnet IDs for the Managed Instances and routing-peer task ENIs. They must provide IPv4 outbound connectivity through NAT or suitable VPC endpoints and, when enable_ipv6 is true, IPv6 through an internet gateway or egress-only internet gateway."
  type        = set(string)

  validation {
    condition     = length(var.subnet_ids) >= 2 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain at least two AWS subnet IDs."
  }
}

variable "enable_ipv6" {
  description = "Enable IPv6 egress for routing-peer task ENIs. The caller must enable ECS dualStackIPv6 and route IPv6-enabled public subnets through an internet gateway or private subnets through an egress-only internet gateway."
  type        = bool
  default     = false
}

variable "image" {
  description = "Pinned NetBird client container image reference. A non-latest tag or sha256 digest is required."
  type        = string

  validation {
    condition = (
      trimspace(var.image) == var.image &&
      can(regex("(:[^/:@]+|@sha256:[0-9a-fA-F]{64})$", var.image)) &&
      !can(regex("(?i):latest$", var.image))
    )
    error_message = "image must end in a pinned non-latest tag or a sha256 digest."
  }
}

variable "management_url" {
  description = "Public HTTPS URL of the NetBird Management service, including an explicit port only when it is not 443."
  type        = string

  validation {
    condition     = can(regex("^https://[A-Za-z0-9.-]+(?::[0-9]{1,5})?$", var.management_url))
    error_message = "management_url must be an HTTPS origin without a path, query, or trailing slash."
  }
}

variable "setup_key_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the NetBird setup key as its complete plaintext value. The secret must use the default Secrets Manager KMS key."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:secretsmanager:[^:]+:[0-9]{12}:secret:.+$", var.setup_key_secret_arn))
    error_message = "setup_key_secret_arn must be a Secrets Manager secret ARN."
  }
}

variable "desired_count" {
  description = "Number of ephemeral routing peers. Use at least two for routing availability."
  type        = number
  default     = 2

  validation {
    condition     = var.desired_count >= 1 && var.desired_count <= 10 && floor(var.desired_count) == var.desired_count
    error_message = "desired_count must be an integer between 1 and 10."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain NetBird client logs in CloudWatch Logs."
  type        = number
  default     = 30

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731,
      1096, 1827, 2192, 2557, 2922, 3288, 3653,
    ], var.log_retention_days)
    error_message = "log_retention_days must be a retention value supported by CloudWatch Logs."
  }
}

variable "tags" {
  description = "Tags to add to all taggable resources created by this module."
  type        = map(string)
  default     = {}
}
