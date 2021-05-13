provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "main" {
  name     = "${var.prefix}ByGuru"
  location = var.location
}

resource "azurerm_virtual_network" "main" {
  name                = "${var.prefix}-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "internal" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_network_security_group" "main" {
  name                = "lb-PublicIP1"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
}

resource "azurerm_public_ip" "main" {
  name                = "TestPublicIP1"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"

  tags = {
    environment = "Production"
  }
}

data "azurerm_public_ip" "main" {
  name                = azurerm_public_ip.main.name
  resource_group_name = azurerm_resource_group.main.name
}

output "public_ip_address" {
  value = data.azurerm_public_ip.main.ip_address
}

#---------------- The Network Security -----------------#
resource "azurerm_network_security_rule" "main-in" {
  name                        = "public"
  priority                    = 300
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "*"
  destination_address_prefix  = data.azurerm_public_ip.main.ip_address
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.main.name
}

resource "azurerm_network_security_rule" "main-out-internal" {
  name                        = "myhttp-lb1"
  priority                    = 200
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "tcp"
  source_port_range           = "80"
  destination_port_range      = "80"
  destination_address_prefix  = "10.0.2.0/24"
  source_address_prefix       = "10.0.2.0/24"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.main.name
}

resource "azurerm_network_security_rule" "main-in-internal" {
  name                        = "myhttp-lb2"
  priority                    = 210
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "tcp"
  source_port_range           = "80"
  source_address_prefix       = "10.0.2.0/24"
  destination_port_range      = "80"
  destination_address_prefix  = "10.0.2.0/24"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.main.name
}

resource "azurerm_subnet_network_security_group_association" "main" {
  subnet_id                 = azurerm_subnet.internal.id
  network_security_group_id = azurerm_network_security_group.main.id
}

#---------------- The Availibility Set -----------------#
resource "azurerm_availability_set" "main" {
  name                = "${var.prefix}-aset"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = {
    environment = "dev"
  }
}

#---------------- The Loadbalancer -----------------#
resource "azurerm_lb" "main" {
  name                = "${var.prefix}-LoadBalancer"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.main.id
  }
}

resource "azurerm_lb_backend_address_pool" "main" {
  resource_group_name = azurerm_resource_group.main.name
  loadbalancer_id     = azurerm_lb.main.id
  name                = "${var.prefix}-BackendAddressPool"
}

resource "azurerm_lb_rule" "example" {
  resource_group_name            = azurerm_resource_group.main.name
  loadbalancer_id                = azurerm_lb.main.id
  name                           = "LBRule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "PublicIPAddress"
  backend_address_pool_id        = azurerm_lb_backend_address_pool.main.id
}

#---------------- The Network Interface -----------------#
resource "azurerm_network_interface" "main" {
  count               = var.number_of_servers
  name                = "${var.server_name}-NIC-${count.index}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  ip_configuration {
    primary                       = true
    name                          = "internal"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
  }
}

#---------------- Associate Backend Address Pool ---------------#
resource "azurerm_network_interface_backend_address_pool_association" "main" {
  count                   = var.number_of_servers
  network_interface_id    = azurerm_network_interface.main[count.index].id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.main.id
} 


#---------------- The Virtual Machine Confifuration -----------------#

# Locate the existing custom/golden image
data "azurerm_image" "search" {
  name                = "GurusPackerMadeImage"
  resource_group_name = "AzureProjectByGuru"
}

resource "azurerm_virtual_machine" "main" {
  count               = var.number_of_servers
  name                = "${var.server_name}-VM-${count.index}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  availability_set_id = azurerm_availability_set.main.id
  vm_size             = "Standard_D2S_v3"

  network_interface_ids = [
    azurerm_network_interface.main[count.index].id
  ]

  storage_image_reference {
    id = data.azurerm_image.search.id
  }

  os_profile {
    computer_name  = "${var.server_name}System${count.index}"
    admin_username = "${var.username}"
    admin_password = "${var.password}"
  }

  storage_os_disk {
    name              = "${var.server_name}myosdisk${count.index}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }
  tags = {
    environment = "production",
    projectname = "GurusAzureProjectOne"

  }
}
