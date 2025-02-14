variable vnet_1_name {
  description = "VNET 1 name"
  type        = string
}

variable vnet_1_id {
  description = "VNET 1 ID"
  type        = string
}

variable vnet_1_rg {
  description = "VNET 1 resource group"
  type        = string
}

variable vnet_2_name {
  description = "VNET 2 name"
  type        = string
}

variable vnet_2_id {
  description = "VNET 2 ID"
  type        = string
}

variable vnet_2_rg {
  description = "VNET 2 resource group"
  type        = string
}

variable hub_to_spokepeering {
  description = "(optional) Peering 1 to 2 name"
  type        = string
  default     = "hubtospoke"
}

variable spoke_to_hubpeering {
  description = "(optional) Peering 2 to 1 name"
  type        = string
  default     = "spoketohub"
}