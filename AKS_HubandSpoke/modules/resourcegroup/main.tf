terraform {
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.15.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = " " // Subscription ID
}

resource "azurerm_resource_group" "hub" {
  name = var.hub_rg
  location = var.location
}

resource "azurerm_resource_group" "spoke" {
  name = var.spoke_rg
  location = var.location
}

