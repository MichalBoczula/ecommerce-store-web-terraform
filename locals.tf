locals {
  names = {
    resource_group = "rg-ecommercestore-web-${var.environment}"
    static_web_app = "swa-ecommercestore-web-${var.environment}"
  }

  tags = {
    project     = "EcommerceStore"
    component   = "web"
    environment = var.environment
    managed_by  = "Terraform"
    purpose     = "portfolio"
  }
}
