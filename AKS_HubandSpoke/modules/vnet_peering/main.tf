resource "azurerm_virtual_network_peering" "peering" {
  name                      = var.hub_to_spokepeering
  resource_group_name       = var.vnet_1_rg
  virtual_network_name      = var.vnet_1_name
  remote_virtual_network_id = var.vnet_2_id
  allow_virtual_network_access = true
  allow_forwarded_traffic = true
}

resource "azurerm_virtual_network_peering" "peering-back" {
  name                      = var.spoke_to_hubpeering
  resource_group_name       = var.vnet_2_rg
  virtual_network_name      = var.vnet_2_name
  remote_virtual_network_id = var.vnet_1_id
  allow_virtual_network_access = true
  allow_forwarded_traffic = true
}