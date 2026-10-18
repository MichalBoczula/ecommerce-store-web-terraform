output "web_deployment" {
  description = "Non-secret hosting targets for the local Angular uploader and later BFF integration."
  value = {
    subscription_id     = var.subscription_id
    resource_group_name = azurerm_resource_group.web.name
    name                = azurerm_static_web_app.web.name
    id                  = azurerm_static_web_app.web.id
    location            = var.location
    hostname            = azurerm_static_web_app.web.default_host_name
    base_url            = "https://${azurerm_static_web_app.web.default_host_name}"
    sku                 = azurerm_static_web_app.web.sku_tier
    bff_link_enabled    = var.bff_backend != null
    bff_resource_id     = var.bff_backend == null ? null : var.bff_backend.resource_id
  }
}
