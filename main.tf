#configuration details of providers
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=0.13"
    }
  }
}

#providers configuration details for azure terraform

provider "azurerm" {
  features {}
}

# IaC to build a resource group

resource "azurerm_resource_group" "res_g" {
  name     = "basic_rg"
  location = "southcentralus"
  tags = {
    envionment = "basic"
    source     = "Terraform"
  }

}