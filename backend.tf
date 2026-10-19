terraform {
  # Independent account; this root owns only its web-specific state blob.
  backend "azurerm" {
    use_cli          = true
    use_azuread_auth = true
  }
}
