mock_provider "azurerm" {
  override_during = plan
}

mock_provider "azapi" {
  override_during = plan
}

override_resource {
  target          = azurerm_static_web_app.web
  override_during = plan
  values = {
    id                = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-ecommercestore-web-dev/providers/Microsoft.Web/staticSites/swa-ecommercestore-web-dev"
    default_host_name = "portfolio-example.azurestaticapps.net"
  }
}

variables {
  subscription_id = "11111111-1111-1111-1111-111111111111"
}

run "standalone_hosting" {
  command = plan

  assert {
    condition = (
      azurerm_resource_group.web.name == "rg-ecommercestore-web-dev" &&
      azurerm_static_web_app.web.name == "swa-ecommercestore-web-dev" &&
      azurerm_static_web_app.web.location == "westeurope" &&
      azurerm_static_web_app.web.sku_tier == "Standard" &&
      azurerm_static_web_app.web.sku_size == "Standard" &&
      !azurerm_static_web_app.web.preview_environments_enabled &&
      azurerm_static_web_app.web.public_network_access_enabled &&
      azurerm_static_web_app.web.configuration_file_changes_enabled
    )
    error_message = "The portfolio site must use public Standard hosting, the web naming convention, and no preview environments."
  }

  assert {
    condition = (
      length(azapi_resource.bff_link) == 0 &&
      !output.web_deployment.bff_link_enabled &&
      output.web_deployment.bff_resource_id == null &&
      output.web_deployment.base_url == "https://portfolio-example.azurestaticapps.net" &&
      output.web_deployment.sku == "Standard"
    )
    error_message = "Hosting must work before a BFF exists and expose a non-secret HTTPS deployment target."
  }
}

run "production_names" {
  command = plan
  variables {
    environment = "prod"
  }
  assert {
    condition = (
      azurerm_resource_group.web.name == "rg-ecommercestore-web-prod" &&
      azurerm_static_web_app.web.name == "swa-ecommercestore-web-prod" &&
      azurerm_static_web_app.web.tags.environment == "prod"
    )
    error_message = "Environment names must remain explicit and independent."
  }
}

run "link_existing_aca_bff" {
  command = plan
  variables {
    bff_backend = {
      resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-ecommercestore-bff-dev/providers/Microsoft.App/containerApps/ca-ecommercestore-bff-dev"
      region      = "northeurope"
    }
  }
  assert {
    condition = (
      length(azapi_resource.bff_link) == 1 &&
      azapi_resource.bff_link["bff"].type == "Microsoft.Web/staticSites/linkedBackends@2024-11-01" &&
      azapi_resource.bff_link["bff"].name == "ca-ecommercestore-bff-dev" &&
      azapi_resource.bff_link["bff"].parent_id == azurerm_static_web_app.web.id &&
      azapi_resource.bff_link["bff"].body.properties.backendResourceId == var.bff_backend.resource_id &&
      azapi_resource.bff_link["bff"].body.properties.region == "northeurope" &&
      output.web_deployment.bff_link_enabled
    )
    error_message = "An optional link must reference the existing ACA app in its own region, using the hosting site as parent."
  }
}

run "reject_invalid_subscription" {
  command = plan
  variables {
    subscription_id = "Portfolio"
  }
  expect_failures = [var.subscription_id]
}

run "reject_invalid_environment" {
  command = plan
  variables {
    environment = "development"
  }
  expect_failures = [var.environment]
}

run "reject_unsupported_static_region" {
  command = plan
  variables {
    location = "northeurope"
  }
  expect_failures = [var.location]
}

run "reject_non_aca_backend" {
  command = plan
  variables {
    bff_backend = {
      resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-example/providers/Microsoft.Web/sites/bff"
      region      = "westeurope"
    }
  }
  expect_failures = [var.bff_backend]
}

run "reject_other_subscription_backend" {
  command = plan
  variables {
    bff_backend = {
      resource_id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-example/providers/Microsoft.App/containerApps/ca-example"
      region      = "northeurope"
    }
  }
  expect_failures = [var.bff_backend]
}

run "reject_backend_url" {
  command = plan
  variables {
    bff_backend = {
      resource_id = "https://bff.example.azurecontainerapps.io"
      region      = "northeurope"
    }
  }
  expect_failures = [var.bff_backend]
}

run "reject_backend_trailing_slash" {
  command = plan
  variables {
    bff_backend = {
      resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-example/providers/Microsoft.App/containerApps/ca-example/"
      region      = "northeurope"
    }
  }
  expect_failures = [var.bff_backend]
}

run "reject_backend_display_region" {
  command = plan
  variables {
    bff_backend = {
      resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-example/providers/Microsoft.App/containerApps/ca-example"
      region      = "North Europe"
    }
  }
  expect_failures = [var.bff_backend]
}
