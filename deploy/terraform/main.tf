terraform {
  required_version = ">= 0.12"
  required_providers {
    random   = "~> 3.1.2"
    azurerm  = "~> 3.1.0"
    azuread  = "~> 2.20.0"
  }
}

# Generate a random suffix for your resources:
resource "random_id" "app-suffix" {
  byte_length = 4
}

provider "azurerm" {
  features {}
}

data "azuread_client_config" "current" {}

# Provision Azure AD App registration:
resource "azuread_application" "app_registration" {
  display_name = "Sample OIDC Auth App ${random_id.app-suffix.hex}"
  owners       = [data.azuread_client_config.current.object_id]
  optional_claims {

    id_token {
      name                  = "ctry"
      source                = null
      essential             = false
      additional_properties = []
    }

    id_token {
      name                  = "family_name"
      source                = null
      essential             = false
      additional_properties = []
    }

    id_token {
      name                  = "given_name"
      source                = null
      essential             = false
      additional_properties = []
    }

    id_token {
      name                  = "groups"
      source                = null
      essential             = false
      additional_properties = []
    }
  }

  sign_in_audience = var.allow_multiple_orgs == true ? "AzureADMultipleOrgs" : "AzureADMyOrg"

  required_resource_access {
    # Microsoft Graph:
    resource_app_id = "00000003-0000-0000-c000-000000000000"

    # ["openid", "profile", "email", "User.Read"] scopes:
    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"
      type = "Scope"
    }
    resource_access {
      id   = "37f7f235-527c-4136-accd-4a02d197296e"
      type = "Scope"
    }

    resource_access {
      id   = "64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0"
      type = "Scope"
    }

    resource_access {
      id   = "14dad69e-099b-42c9-810b-d002981feec1"
      type = "Scope"
    }

  }

  web {
    homepage_url  = "https://sample-oidc-client-app-${random_id.app-suffix.hex}.azurewebsites.net"
    logout_url    = "https://sample-oidc-client-app-${random_id.app-suffix.hex}.azurewebsites.net/logout"
    redirect_uris = ["https://sample-oidc-client-app-${random_id.app-suffix.hex}.azurewebsites.net/callback"]

    implicit_grant {
      access_token_issuance_enabled = true
      id_token_issuance_enabled     = true
    }
  }
}

resource "azuread_application_password" "app_registration_secret" {
  display_name          = "OIDC Client Secret"
  application_object_id = azuread_application.app_registration.object_id
}


# Provision a resource group:
resource "azurerm_resource_group" "sample_oidc_app_resource_group" {
  name     = "sample-oidc-client-app-${random_id.app-suffix.hex}"
  location = var.location
}

# Provision ACR repo:
resource "azurerm_container_registry" "acr_repo" {
  name                = "sampleoidcclientapp${random_id.app-suffix.hex}"
  resource_group_name = azurerm_resource_group.sample_oidc_app_resource_group.name
  location            = var.location
  sku                 = "Standard" # Or "Premium"?
  admin_enabled       = false
}

# Tag and push image to ACR:
resource "null_resource" "docker_push" {
  provisioner "local-exec" {
    command = <<-EOF
        az acr login --name sampleoidcclientapp${random_id.app-suffix.hex} --subscription ${var.subscription_id}
        docker tag sample-oidc-client-app:latest sampleoidcclientapp${random_id.app-suffix.hex}.azurecr.io/sample-oidc-client-app:latest
        docker push sampleoidcclientapp${random_id.app-suffix.hex}.azurecr.io/sample-oidc-client-app:latest
      EOF
  }
  depends_on = [azurerm_container_registry.acr_repo]
}

# Provision App Service Plan:
resource "azurerm_service_plan" "sample_oidc_app_svc_plan" {
  name                = "sample-oidc-client-app-${random_id.app-suffix.hex}"
  location            = var.location
  resource_group_name = azurerm_resource_group.sample_oidc_app_resource_group.name
  os_type             = "Linux"
  sku_name            = "B1"
  depends_on          = [null_resource.docker_push]
}

resource "azurerm_linux_web_app" "sample_oidc_app_svc" {
  name                = "sample-oidc-client-app-${random_id.app-suffix.hex}"
  location            = var.location
  resource_group_name = azurerm_resource_group.sample_oidc_app_resource_group.name
  service_plan_id     = azurerm_service_plan.sample_oidc_app_svc_plan.id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    container_registry_use_managed_identity = true

    application_stack {
      docker_image     = "sampleoidcclientapp${random_id.app-suffix.hex}.azurecr.io/sample-oidc-client-app"
      docker_image_tag = "latest"
    }
  }

  app_settings = {
    "WEBSITES_PORT"      = "3000"
    "OIDC_CLIENT_ID"     = azuread_application.app_registration.application_id
    "OIDC_CLIENT_SECRET" = azuread_application_password.app_registration_secret.value
    "OIDC_ISSUER"        = var.allow_multiple_orgs == true ? "https://login.microsoftonline.com/common/v2.0" : "https://login.microsoftonline.com/${var.tenant_id}/v2.0"
    "SERVICE_URL"        = "https://sample-oidc-client-app-${random_id.app-suffix.hex}.azurewebsites.net"
  }

  depends_on = [null_resource.docker_push]
}

resource "azurerm_role_assignment" "app_service_managed_identity" {
  scope                = azurerm_container_registry.acr_repo.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.sample_oidc_app_svc.identity.0.principal_id
}


output "instructions" {
  value = <<EOF
    ✅ Check your application's health here:

        https://sample-oidc-client-app-${random_id.app-suffix.hex}.azurewebsites.net/health

    ✅ Log into the application here:

        https://sample-oidc-client-app-${random_id.app-suffix.hex}.azurewebsites.net
  EOF
}
