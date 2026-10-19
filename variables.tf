variable "subscription_id" {
  description = "Azure subscription UUID; select the same subscription in Azure CLI."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be an Azure subscription UUID."
  }
}

variable "environment" {
  description = "Naming component. Use a separate backend key for each environment."
  type        = string
  default     = "dev"
  nullable    = false

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be dev, test or prod."
  }
}

variable "location" {
  description = "Static Web Apps backend/staging region; static files are distributed globally."
  type        = string
  default     = "westeurope"
  nullable    = false

  validation {
    condition     = contains(["westeurope", "centralus", "eastus2", "westus2", "eastasia"], var.location)
    error_message = "Choose a supported initial Static Web Apps region: westeurope, centralus, eastus2, westus2 or eastasia."
  }
}

variable "bff_backend" {
  description = "Optional existing ACA BFF to link to production /api. Supply only after its external ingress and /api routes are ready."
  type = object({
    resource_id = string
    region      = string
  })
  default = null

  validation {
    condition = var.bff_backend == null ? true : can(regex(
      "(?i)^/subscriptions/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/resourceGroups/[a-z0-9_.()-]+/providers/Microsoft\\.App/containerApps/[a-z0-9][a-z0-9-]*[a-z0-9]$",
      var.bff_backend.resource_id
    ))
    error_message = "bff_backend.resource_id must be a full Microsoft.App/containerApps resource ID, without a trailing slash."
  }

  validation {
    condition = var.bff_backend == null ? true : try(
      lower(split("/", var.bff_backend.resource_id)[2]) == lower(var.subscription_id), false
    )
    error_message = "The BFF must belong to subscription_id."
  }

  validation {
    condition     = var.bff_backend == null ? true : can(regex("^[a-z][a-z0-9]+$", var.bff_backend.region))
    error_message = "bff_backend.region must be an Azure region identifier, such as northeurope."
  }
}
