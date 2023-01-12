variable "location"{
    type=string
    description = "location of resource group"
}

variable "nsg_rules"{
    type=list(object({
    name                       = string
    priority                   = number
    direction                  = string
    access                     = string
    protocol                   = string
    source_port_range          = string
    destination_port_range     = string
    source_address_prefix      = string
    destination_address_prefix = string
    }))

    description = "values for each NSG rule"
}