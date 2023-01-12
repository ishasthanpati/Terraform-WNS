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

#resource group
resource "azurerm_resource_group" "windows-rg" {
  name     = "windows-resources"
  location = var.location
}

#virtual network
resource "azurerm_virtual_network" "windows-vn" {
  name                = "win-network"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.windows-rg.name
}

#subnet for webserver
resource "azurerm_subnet" "windows-subnet1" {
  name                 = "win-internal1"
  resource_group_name  = azurerm_resource_group.windows-rg.name
  virtual_network_name = azurerm_virtual_network.windows-vn.name
  address_prefixes     = ["10.0.2.0/24"]
}

#subnet for db server
resource "azurerm_subnet" "windows-subnet2" {
  name                 = "win-internal2"
  resource_group_name  = azurerm_resource_group.windows-rg.name
  virtual_network_name = azurerm_virtual_network.windows-vn.name
  address_prefixes     = ["10.0.1.0/24"]
}

#public ip for nat gateway
resource "azurerm_public_ip" "public-ip-nat" {
  name                = "nat-gateway-publicIP"
  location            = azurerm_resource_group.windows-rg.location
  resource_group_name = azurerm_resource_group.windows-rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1"]
}

#public ip prefix for nat gateway
resource "azurerm_public_ip_prefix" "public-ip-pref-nat" {
  name                = "nat-gateway-publicIPPrefix"
  location            = azurerm_resource_group.windows-rg.location
  resource_group_name = azurerm_resource_group.windows-rg.name
  prefix_length       = 30
  zones               = ["1"]
}

#network gateway for egress traffic access
resource "azurerm_nat_gateway" "windows-nat-gw" {
  name                = "natgateway"
  location            = var.location
  resource_group_name = azurerm_resource_group.windows-rg.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  zones                   = ["1"]
}

# Nat Gateway and a Public IP Association
resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.windows-nat-gw.id
  public_ip_address_id = azurerm_public_ip.public-ip-nat.id
}

# Nat Gateway and a Public IP Prefix Association
resource "azurerm_nat_gateway_public_ip_prefix_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.windows-nat-gw.id
  public_ip_prefix_id = azurerm_public_ip_prefix.public-ip-pref-nat.id
}

#nat-gw subnet2 association
resource "azurerm_subnet_nat_gateway_association" "nat-association" {
  subnet_id      = azurerm_subnet.windows-subnet2.id
  nat_gateway_id = azurerm_nat_gateway.windows-nat-gw.id
}

#public ip for vm webserver
resource "azurerm_public_ip" "windows-public_ip" {
  name                = "win-vm_public_ip"
  resource_group_name = azurerm_resource_group.windows-rg.name
  location            = var.location
  allocation_method   = "Dynamic"
}

#nic for webserver
resource "azurerm_network_interface" "windows-nic-public" {
  name                = "win-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.windows-rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.windows-subnet1.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.windows-public_ip.id
  }
}

#nic for db server
resource "azurerm_network_interface" "windows-nic-priv" {
  name                = "win-nic2"
  location            = var.location
  resource_group_name = azurerm_resource_group.windows-rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.windows-subnet2.id
    private_ip_address_allocation = "Dynamic"
  }
}

#network security group
resource "azurerm_network_security_group" "windows-nsg" {
  name                = "win-acceptanceTestSecurityGroup1"
  location            = var.location
  resource_group_name = azurerm_resource_group.windows-rg.name

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
  network_interface_id      = azurerm_network_interface.windows-nic-public.id
  network_security_group_id = azurerm_network_security_group.windows-nsg.id
}

#nsg nic for db server
resource "azurerm_network_interface_security_group_association" "association2" {
  network_interface_id      = azurerm_network_interface.windows-nic-priv.id
  network_security_group_id = azurerm_network_security_group.windows-nsg.id
}

#vm for webserver
resource "azurerm_windows_virtual_machine" "windows-vm-pub" {
  name                = "webserver"
  resource_group_name = azurerm_resource_group.windows-rg.name
  location            = var.location
  size                = "Standard_F2"
  admin_username      = var.win-uid
  admin_password      = var.win-pass
  network_interface_ids = [
    azurerm_network_interface.windows-nic-public.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }
}

#vm for db server
resource "azurerm_windows_virtual_machine" "windows-vm-priv" {
  name                = "db-server"
  resource_group_name = azurerm_resource_group.windows-rg.name
  location            = var.location
  size                = "Standard_F2"
  admin_username      = var.win-uid
  admin_password      = var.win-pass
  network_interface_ids = [
    azurerm_network_interface.windows-nic-priv.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }
}

#windows app service
resource "azurerm_service_plan" "windows-plan" {
  name                = "service_plan"
  resource_group_name = azurerm_resource_group.windows-rg.name
  location            = var.location
  os_type             = "Windows"
  sku_name            = "B1"
}

resource "azurerm_windows_web_app" "windows-app" {
  name                = "Windows-web-app-server-wns"
  resource_group_name = azurerm_resource_group.windows-rg.name
  location            = azurerm_service_plan.windows-plan.location
  service_plan_id     = azurerm_service_plan.windows-plan.id

  site_config {}
}

