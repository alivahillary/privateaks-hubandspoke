data "azurerm_resource_group" "hub" {
  name = var.hub_rg
}

data "azurerm_resource_group" "spoke" {
  name = var.spoke_rg
}

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
  subscription_id = " " # Azure Subscription ID
}


module "hub_network" {
  source              = "./modules/vnets"
  resource_group_name = data.azurerm_resource_group.hub.name
  location            = var.location
  vnet_name           = var.hub_vnet_name
  address_space       = ["10.0.0.0/22"]
  subnets = [
    {
      name : "AzureFirewallSubnet"
      address_prefixes : ["10.0.0.0/24"]
    },
    {
      name : "jumpbox-subnet"
      address_prefixes : ["10.0.1.0/24"]
    }
  ]
}

module "kube_network" {
  source              = "./modules/vnets"
  resource_group_name = data.azurerm_resource_group.spoke.name
  location            = var.location
  vnet_name           = var.spoke_vnet_name
  address_space       = ["10.0.4.0/22"]
  subnets = [
    {
      name : "aks-subnet"
      address_prefixes : ["10.0.5.0/24"]
    }
  ]
}

module "vnet_peering" {
  source      = "./modules/vnet_peering"
  vnet_1_name = var.hub_vnet_name
  vnet_1_id   = module.hub_network.vnet_id
  vnet_1_rg   = data.azurerm_resource_group.hub.name
  vnet_2_name = var.spoke_vnet_name
  vnet_2_id   = module.kube_network.vnet_id
  vnet_2_rg   = data.azurerm_resource_group.spoke.name
}

module "firewall" {
  source         = "./modules/firewall"
  resource_group = data.azurerm_resource_group.hub.name
  location       = var.location
  pip_name       = "azureFirewalls-ip"
  fw_name        = "kubenetfw"
  subnet_id      = module.hub_network.subnet_ids["AzureFirewallSubnet"]
}

module "routetable" {
  source             = "./modules/route_table"
  resource_group     = data.azurerm_resource_group.hub.name
  location           = var.location
  rt_name            = "kubenetfw_fw_rt"
  r_name             = "kubenetfw_fw_r"
  firewall_private_ip = module.firewall.fw_private_ip
  subnet_id          = module.kube_network.subnet_ids["aks-subnet"]
}

# data "azurerm_kubernetes_service_versions" "current" {
#   location       = var.location
#   version_prefix = var.kube_version_prefix
# }


resource "azurerm_kubernetes_cluster" "aks" {
  name                    = "quareis-aks"
  location                = var.location
  resource_group_name     = var.spoke_rg
  dns_prefix              = "aksdns"
  kubernetes_version      = "1.31" # Replace with the desired version
  private_cluster_enabled = true
  private_cluster_public_fqdn_enabled     = false
  # public_network_access_enabled           = true


  default_node_pool {
    name           = "default"
    node_count     = var.nodepool_nodes_count
    vm_size        = var.nodepool_vm_size
    vnet_subnet_id = module.kube_network.subnet_ids["aks-subnet"]
  }

  identity {
    type = "SystemAssigned"
  }


  network_profile {
    network_plugin     = "azure"
    outbound_type      = "userDefinedRouting"
    dns_service_ip     = var.network_dns_service_ip
    service_cidr       = var.network_service_cidr
    load_balancer_sku = "standard"


  }

  depends_on = [module.routetable]
}

resource "local_file" "kubeconfig" {
  depends_on   = [azurerm_kubernetes_cluster.aks]
  filename     = "kubeconfig"
  content      = azurerm_kubernetes_cluster.aks.kube_config_raw
}

# #Assign Network Contributor role to AKS cluster identity

resource "azurerm_role_assignment" "netcontributor" {
  role_definition_name = "Network Contributor"
  scope                = module.kube_network.subnet_ids["aks-subnet"]
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id
}

module "jumpbox" {
  source                  = "./modules/jumpbox"
  location                = var.location
  resource_group          = data.azurerm_resource_group.hub.name
  vnet_id                 = module.hub_network.vnet_id
  subnet_id               = module.hub_network.subnet_ids["jumpbox-subnet"]
  dns_zone_name           = join(".", slice(split(".", azurerm_kubernetes_cluster.aks.private_fqdn), 1, length(split(".", azurerm_kubernetes_cluster.aks.private_fqdn))))
  dns_zone_resource_group = azurerm_kubernetes_cluster.aks.node_resource_group
}




