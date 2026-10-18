resource "azurerm_resource_group" "web" {
  name     = local.names.resource_group
  location = var.location
  tags     = local.tags
}

resource "azurerm_static_web_app" "web" {
  name                = local.names.static_web_app
  resource_group_name = azurerm_resource_group.web.name
  location            = var.location

  # Standard supports a linked ACA BFF. No enterprise edge/CDN add-on.
  sku_tier                           = "Standard"
  sku_size                           = "Standard"
  preview_environments_enabled       = false
  public_network_access_enabled      = true
  configuration_file_changes_enabled = true
  tags                               = local.tags

  # Token-based uploads can populate repository metadata without configuring
  # a repository-admin token. That metadata is not our deployment mechanism.
  lifecycle {
    ignore_changes = [repository_branch, repository_url]
  }
}

# Omitted by default so hosting can be applied before the BFF exists. Azure's
# linking API configures the linked-SWA authentication provider on the BFF.
# Removing the link does not automatically remove that provider from the BFF.
resource "azapi_resource" "bff_link" {
  for_each  = var.bff_backend == null ? {} : { bff = var.bff_backend }
  type      = "Microsoft.Web/staticSites/linkedBackends@2024-11-01"
  name      = basename(each.value.resource_id)
  parent_id = azurerm_static_web_app.web.id

  body = {
    properties = {
      backendResourceId = each.value.resource_id
      region            = each.value.region
    }
  }
}
