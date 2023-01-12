win-uid = "wnsadmin"
win-pass = "Wns$1234"
location= "West Europe"

nsg_rules=[
    {
        name                       = "Port3389Access"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "3389"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
]