variable "name" {
  description = "Short name used for resources created by this relay site."
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
  description = "ID of the VPC in which to deploy the relay site."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be an AWS VPC ID."
  }
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the internet-facing Network Load Balancer."
  type        = set(string)

  validation {
    condition     = length(var.public_subnet_ids) > 0 && alltrue([for id in var.public_subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "public_subnet_ids must contain at least one AWS subnet ID."
  }
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the Fargate task. They must provide NAT or the required VPC endpoints."
  type        = set(string)

  validation {
    condition     = length(var.private_subnet_ids) > 0 && alltrue([for id in var.private_subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "private_subnet_ids must contain at least one AWS subnet ID."
  }
}

variable "fqdn" {
  description = "Public DNS name advertised to NetBird peers, without a trailing dot."
  type        = string

  validation {
    condition = (
      length(var.fqdn) <= 253 &&
      var.fqdn == lower(var.fqdn) &&
      !endswith(var.fqdn, ".") &&
      length(split(".", var.fqdn)) >= 2 &&
      alltrue([
        for label in split(".", var.fqdn) :
        can(regex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$", label))
      ])
    )
    error_message = "fqdn must be a lowercase DNS name without a trailing dot."
  }
}

variable "route53_zone_id" {
  description = "ID of the existing public Route 53 hosted zone in which to create the Relay record."
  type        = string

  validation {
    condition     = can(regex("^Z[A-Z0-9]+$", var.route53_zone_id))
    error_message = "route53_zone_id must be a Route 53 hosted zone ID."
  }
}

variable "certificate_arn" {
  description = "ARN of an existing ACM certificate covering fqdn. It must be in the relay site's AWS region."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:acm:[^:]+:[0-9]{12}:certificate/.+$", var.certificate_arn))
    error_message = "certificate_arn must be an ACM certificate ARN."
  }
}

variable "relay_auth_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the relay authentication secret as its plaintext value."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:secretsmanager:[^:]+:[0-9]{12}:secret:.+$", var.relay_auth_secret_arn))
    error_message = "relay_auth_secret_arn must be a Secrets Manager secret ARN."
  }
}

variable "image" {
  description = "Pinned NetBird Relay container image reference. A non-latest tag or sha256 digest is required."
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

variable "cpu" {
  description = "Fargate task CPU units."
  type        = number
  default     = 256

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.cpu)
    error_message = "cpu must be a supported Fargate CPU value."
  }
}

variable "memory" {
  description = "Fargate task memory in MiB. The selected value must be valid for cpu."
  type        = number
  default     = 512

  validation {
    condition     = var.memory >= 512 && var.memory <= 122880 && floor(var.memory) == var.memory
    error_message = "memory must be between 512 and 122880 MiB."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain Relay logs in CloudWatch Logs."
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
