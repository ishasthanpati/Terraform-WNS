terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
}

resource "tls_private_key" "linux_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# We want to save the private key to our machine
# We can then use this key to connect to our Linux VM

resource "local_file" "linuxkey" {
  filename = "linuxkey.pem"
  content  = tls_private_key.linux_key.private_key_pem
}

#resource group
resource "azurerm_resource_group" "linux-rg" {
  name     = "linux-resources"
  location = var.location
}

#virtual network
resource "azurerm_virtual_network" "linux-vn" {
  name                = "linux-virtual-network"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.linux-rg.name
}

#subnet for webserver
resource "azurerm_subnet" "linux-subnet1" {
  name                 = "internal-subnet1"
  resource_group_name  = azurerm_resource_group.linux-rg.name
  virtual_network_name = azurerm_virtual_network.linux-vn.name
  address_prefixes     = ["10.0.3.0/24"]
}

#subnet for db server
resource "azurerm_subnet" "linux-subnet2" {
  name                 = "internal-subnet2"
  resource_group_name  = azurerm_resource_group.linux-rg.name
  virtual_network_name = azurerm_virtual_network.linux-vn.name
  address_prefixes     = ["10.0.4.0/24"]
}

#public ip for nat gateway
resource "azurerm_public_ip" "public-ip-nat" {
  name                = "nat-gateway-publicIP"
  location            = azurerm_resource_group.linux-rg.location
  resource_group_name = azurerm_resource_group.linux-rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1"]
}

#public ip prefix for nat gateway
resource "azurerm_public_ip_prefix" "public-ip-pref-nat" {
  name                = "nat-gateway-publicIPPrefix"
  location            = azurerm_resource_group.linux-rg.location
  resource_group_name = azurerm_resource_group.linux-rg.name
  prefix_length       = 30
  zones               = ["1"]
}

#network gateway for egress traffic access
resource "azurerm_nat_gateway" "linux-nat-gw" {
  name                = "natgateway"
  location            = var.location
  resource_group_name = azurerm_resource_group.linux-rg.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  zones                   = ["1"]
}

# Nat Gateway and a Public IP Association
resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.linux-nat-gw.id
  public_ip_address_id = azurerm_public_ip.public-ip-nat.id
}

# Nat Gateway and a Public IP Prefix Association
resource "azurerm_nat_gateway_public_ip_prefix_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.linux-nat-gw.id
  public_ip_prefix_id = azurerm_public_ip_prefix.public-ip-pref-nat.id
}

#nat-gw subnet2 association
resource "azurerm_subnet_nat_gateway_association" "nat-association" {
  subnet_id      = azurerm_subnet.linux-subnet2.id
  nat_gateway_id = azurerm_nat_gateway.linux-nat-gw.id
}

#public ip for vm webserver
resource "azurerm_public_ip" "linux-public_ip" {
  name                = "vm_public_ip"
  resource_group_name = azurerm_resource_group.linux-rg.name
  location            = var.location
  allocation_method   = "Dynamic"
}

#nic for webserver
resource "azurerm_network_interface" "linux-nic-public" {
  name                = "nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.linux-rg.name

  ip_configuration {
    name                          = "internal-ip1"
    subnet_id                     = azurerm_subnet.linux-subnet1.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.linux-public_ip.id
  }
}

#nic for db server
resource "azurerm_network_interface" "linux-nic-priv" {
  name                = "nic2"
  location            = var.location
  resource_group_name = azurerm_resource_group.linux-rg.name

  ip_configuration {
    name                          = "internal-ip2"
    subnet_id                     = azurerm_subnet.linux-subnet2.id
    private_ip_address_allocation = "Dynamic"
  }
}

#network security group
resource "azurerm_network_security_group" "linux-nsg" {
  name                = "acceptanceTestSecurityGroup1"
  location            = var.location
  resource_group_name = azurerm_resource_group.linux-rg.name

  dynamic "security_rule" {
    for_each = var.nsg_rules
    content {
      name                       = security_rule.value["name"]
      priority                   = security_rule.value["priority"]
      direction                  = security_rule.value["direction"]
      access                     = security_rule.value["access"]
      protocol                   = security_rule.value["protocol"]
      source_port_range          = security_rule.value["source_port_range"]
      destination_port_range     = security_rule.value["destination_port_range"]
      source_address_prefix      = security_rule.value["source_address_prefix"]
      destination_address_prefix = security_rule.value["destination_address_prefix"]
    }
  }
}

#nsg nic for webserver
resource "azurerm_network_interface_security_group_association" "association1" {
  network_interface_id      = azurerm_network_interface.linux-nic-public.id
  network_security_group_id = azurerm_network_security_group.linux-nsg.id
}

#nsg nic for db server
resource "azurerm_network_interface_security_group_association" "association2" {
  network_interface_id      = azurerm_network_interface.linux-nic-priv.id
  network_security_group_id = azurerm_network_security_group.linux-nsg.id
}

#vm for webserver
resource "azurerm_linux_virtual_machine" "linux-vm-pub" {
  name                = "webserver"
  resource_group_name = azurerm_resource_group.linux-rg.name
  location            = var.location
  size                = "Standard_F2"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.linux-nic-public.id,
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = tls_private_key.linux_key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
  depends_on = [
    azurerm_network_interface.linux-nic-public,
    tls_private_key.linux_key
  ]
  provisioner "file" {
    source      = "linuxkey.pem"
    destination = "/home/adminuser/linuxkey.pem"

    connection {
      type        = "ssh"
      user        = "adminuser"
      private_key = tls_private_key.linux_key.private_key_pem
      host        = self.public_ip_address
    }
  }
}

#vm for db server
resource "azurerm_linux_virtual_machine" "linux-vm-priv" {
  name                = "db-server"
  resource_group_name = azurerm_resource_group.linux-rg.name
  location            = var.location
  size                = "Standard_F2"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.linux-nic-priv.id,
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = tls_private_key.linux_key.public_key_openssh
  }


  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

}

#linux app service
resource "azurerm_service_plan" "linux-plan" {
  name                = "service_plan"
  resource_group_name = azurerm_resource_group.linux-rg.name
  location            = var.location
  os_type             = "Linux"
  sku_name            = "B1"
}

resource "azurerm_linux_web_app" "linux-app" {
  name                = "Linux-web-app-server-wns"
  resource_group_name = azurerm_resource_group.linux-rg.name
  location            = var.location
  service_plan_id     = azurerm_service_plan.linux-plan.id

  site_config {}
}