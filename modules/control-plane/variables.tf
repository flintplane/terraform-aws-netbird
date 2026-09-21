variable "name" {
  description = "Short name used for resources created by the control plane."
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
  description = "ID of the existing VPC in which to deploy the control plane."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be an AWS VPC ID."
  }
}

variable "public_subnet_ids" {
  description = "Existing public subnet IDs for the internet-facing Application Load Balancer."
  type        = set(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2 && alltrue([for id in var.public_subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "public_subnet_ids must contain at least two AWS subnet IDs."
  }
}

variable "private_subnet_ids" {
  description = "Existing private subnet IDs for Fargate tasks and the RDS subnet group. They must span at least two Availability Zones."
  type        = set(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2 && alltrue([for id in var.private_subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "private_subnet_ids must contain at least two AWS subnet IDs."
  }
}

variable "enable_ipv6" {
  description = "Expose the public Application Load Balancer and endpoint DNS names over both IPv4 and IPv6. Backend target groups remain IPv4."
  type        = bool
  default     = false
}

variable "endpoints" {
  description = "Public DNS names for the independently routed control-plane services."
  type = object({
    management_fqdn = string
    signal_fqdn     = string
    dashboard_fqdn  = string
  })

  validation {
    condition = alltrue([
      for fqdn in [var.endpoints.management_fqdn, var.endpoints.signal_fqdn, var.endpoints.dashboard_fqdn] :
      length(fqdn) <= 253 && fqdn == lower(fqdn) && !endswith(fqdn, ".") && length(split(".", fqdn)) >= 2 && alltrue([
        for label in split(".", fqdn) : can(regex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$", label))
      ])
    ])
    error_message = "Each endpoint must be a lowercase DNS name without a trailing dot."
  }

  validation {
    condition     = length(toset([var.endpoints.management_fqdn, var.endpoints.signal_fqdn, var.endpoints.dashboard_fqdn])) == 3
    error_message = "management_fqdn, signal_fqdn, and dashboard_fqdn must be distinct."
  }
}

variable "route53_zone_id" {
  description = "ID of the existing Route53 hosted zone in which to create endpoint records."
  type        = string

  validation {
    condition     = can(regex("^Z[A-Z0-9]+$", var.route53_zone_id))
    error_message = "route53_zone_id must be a Route53 hosted zone ID."
  }
}

variable "certificate_arn" {
  description = "ARN of an existing ACM certificate covering all endpoint names. It must be in the deployment region."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:acm:[^:]+:[0-9]{12}:certificate/.+$", var.certificate_arn))
    error_message = "certificate_arn must be an ACM certificate ARN."
  }
}

variable "images" {
  description = "Pinned full image references for the three separate NetBird services."
  type = object({
    management = string
    signal     = string
    dashboard  = string
  })

  validation {
    condition = alltrue([
      for image in [var.images.management, var.images.signal, var.images.dashboard] :
      trimspace(image) == image &&
      can(regex("(:[^/:@]+|@sha256:[0-9a-fA-F]{64})$", image)) &&
      !can(regex("(?i):latest$", image))
    ])
    error_message = "Every image must end in a pinned non-latest tag or a sha256 digest."
  }
}

variable "relay" {
  description = "External Relay and STUN endpoints advertised by Management. The secret must match every referenced Relay site."
  type = object({
    auth_secret_arn = string
    addresses       = set(string)
    stun_uris       = set(string)
  })

  validation {
    condition     = can(regex("^arn:[^:]+:secretsmanager:[^:]+:[0-9]{12}:secret:.+$", var.relay.auth_secret_arn))
    error_message = "relay.auth_secret_arn must be a Secrets Manager secret ARN."
  }

  validation {
    condition     = length(var.relay.addresses) > 0 && alltrue([for address in var.relay.addresses : can(regex("^rels://[^/]+:[0-9]+$", address))])
    error_message = "relay.addresses must contain at least one rels://host:port URI."
  }

  validation {
    condition     = length(var.relay.stun_uris) > 0 && alltrue([for uri in var.relay.stun_uris : can(regex("^stun:[^/]+:[0-9]+$", uri))])
    error_message = "relay.stun_uris must contain at least one stun:host:port URI."
  }
}

variable "local_auth_disabled" {
  description = "Disable embedded email/password authentication after an external identity provider and external Owner have been verified. Leave false for initial bootstrap and break-glass recovery."
  type        = bool
  default     = false
}

variable "netbird_dns_domain" {
  description = "Private suffix appended to peer names for NetBird DNS resolution."
  type        = string

  validation {
    condition = (
      length(var.netbird_dns_domain) <= 192 &&
      var.netbird_dns_domain == lower(var.netbird_dns_domain) &&
      !endswith(var.netbird_dns_domain, ".") &&
      alltrue([for label in split(".", var.netbird_dns_domain) : can(regex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$", label))])
    )
    error_message = "netbird_dns_domain must be a lowercase DNS suffix of at most 192 characters without a trailing dot."
  }
}

variable "single_account_mode_domain" {
  description = "Identity domain used to group first-login users into one NetBird account."
  type        = string

  validation {
    condition = (
      length(var.single_account_mode_domain) <= 253 &&
      var.single_account_mode_domain == lower(var.single_account_mode_domain) &&
      !endswith(var.single_account_mode_domain, ".") &&
      alltrue([for label in split(".", var.single_account_mode_domain) : can(regex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$", label))])
    )
    error_message = "single_account_mode_domain must be a lowercase DNS domain without a trailing dot."
  }
}

variable "database" {
  description = "Provisioned PostgreSQL settings."
  type = object({
    engine_version        = optional(string, "16")
    instance_class        = optional(string, "db.t4g.small")
    allocated_storage_gib = optional(number, 20)
    max_storage_gib       = optional(number, 100)
    backup_retention_days = optional(number, 7)
    multi_az              = optional(bool, false)
    deletion_protection   = optional(bool, false)
    password_version      = optional(number, 1)
  })
  default = {}

  validation {
    condition = (
      var.database.allocated_storage_gib >= 20 &&
      var.database.max_storage_gib >= ceil(var.database.allocated_storage_gib * 1.1) &&
      var.database.backup_retention_days >= 0 && var.database.backup_retention_days <= 35 &&
      var.database.password_version >= 1 && floor(var.database.password_version) == var.database.password_version
    )
    error_message = "Database storage must be at least 20 GiB, max storage must be at least 10 percent higher, backup retention must be 0-35 days, and password_version must be a positive integer."
  }
}

variable "service_resources" {
  description = "Fargate sizing and Dashboard replica count for each independent service."
  type = object({
    management = optional(object({
      cpu    = optional(number, 512)
      memory = optional(number, 1024)
    }), {})
    signal = optional(object({
      cpu    = optional(number, 256)
      memory = optional(number, 512)
    }), {})
    dashboard = optional(object({
      cpu           = optional(number, 256)
      memory        = optional(number, 512)
      desired_count = optional(number, 1)
    }), {})
  })
  default = {}

  validation {
    condition = alltrue([
      for service in [var.service_resources.management, var.service_resources.signal, var.service_resources.dashboard] :
      contains([256, 512, 1024, 2048, 4096, 8192, 16384], service.cpu) &&
      service.memory >= 512 && service.memory <= 122880 && floor(service.memory) == service.memory
    ])
    error_message = "Each service must use a supported Fargate CPU value and integer memory between 512 and 122880 MiB."
  }

  validation {
    condition     = var.service_resources.dashboard.desired_count >= 1 && floor(var.service_resources.dashboard.desired_count) == var.service_resources.dashboard.desired_count
    error_message = "Dashboard desired_count must be a positive integer."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain service logs in CloudWatch Logs."
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
