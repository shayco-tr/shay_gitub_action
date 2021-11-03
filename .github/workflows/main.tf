#create resource group
locals{
  env_name = (terraform.workspace == "stage") ? "stage" : "prod"
}

resource "azurerm_resource_group" "rg" { 
    name     = "${local.env_name}_${var.resource_group_name}"
    location = var.location
}
#Create virtual network
resource "azurerm_virtual_network" "vnet" {
    name = "${local.env_name}_${var.resource_group_name}"
    address_space      = var.vnet_address_space
    location            = var.location
    resource_group_name = azurerm_resource_group.rg.name
}
# create availability set
resource "azurerm_availability_set" "avs" {
  name                = "${local.env_name}_avs"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
}
# Create subnet
resource "azurerm_subnet" "subnet" {
count = length(var.subnet)
  name                 =  "${local.env_name}_${var.prefix}-nm${count.index}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  #address_prefix  =  [var.subnet[count.index]]
  #address_prefix = [element(var.subnet, count.index)]
   address_prefix  = var.subnet[count.index]
}
# Create network interface
resource "azurerm_network_interface" "nic" {
  count = 2
  name                      = "ni${count.index}-nic"
  location                  = var.location
  resource_group_name       = azurerm_resource_group.rg.name
ip_configuration {
    name                          = "test"
    subnet_id                     = element(azurerm_subnet.subnet, 0).id
    private_ip_address_allocation = "dynamic"
  }
}

# Create virtual machine
resource "azurerm_virtual_machine" "vm" {
  count = 2
  name                  = "nm${count.index}-vm"
  location              = var.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.nic[count.index].id]
  vm_size               = "Standard_DS1_v2"
  availability_set_id   = azurerm_availability_set.avs.id
  #zones = [count.index+1]
  storage_os_disk {
    name              = "stvm${count.index}os"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = lookup(var.managed_disk_type, var.location, "Standard_LRS")
  }

  storage_image_reference {
    publisher = var.os.publisher
    offer     = var.os.offer
    sku       = var.os.sku
    version   = var.os.version
  }

  os_profile {
    computer_name  = var.servername
    admin_username = "shay"
  }
    os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      key_data = file("/home/shay/.ssh/id_rsa.pub")
      path     = "/home/shay/.ssh/authorized_keys"
    }
  }
}
#data "azurerm_resource_group" "rgn" {
#    name = "shayntnew"
#}
data "azurerm_resource_group" "rgy" {
    name = "bastion1"
}
data "azurerm_virtual_network" "vnety" {
    name = "bastion1"
    resource_group_name = data.azurerm_resource_group.rgy.name
}
#resource "azurerm_resource_group" "lbg" {
#  name     = "LoadBalancerRG"
#  location = var.location
#}

resource "azurerm_public_ip" "pi" {
  name                = "PublicIPForLB"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
}

resource "azurerm_lb" "lb" {
  name   = "TestLoadBalancer"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.pi.id
  }
}
resource "azurerm_lb_backend_address_pool" "albap" {
  resource_group_name = azurerm_resource_group.rg.name
  loadbalancer_id     = azurerm_lb.lb.id
  name                = "acctestpool"
}

resource "azurerm_network_interface_backend_address_pool_association" "ibdpa" {
  count = 2
  network_interface_id    = azurerm_network_interface.nic[count.index].id
  ip_configuration_name   = "test"
  backend_address_pool_id = azurerm_lb_backend_address_pool.albap.id
}
resource "azurerm_lb_rule" "lbrl" {
 resource_group_name            = azurerm_resource_group.rg.name
  loadbalancer_id                = azurerm_lb.lb.id
  name                           = "LBRule"
  protocol                       = "Tcp"
  frontend_port                  = 8080
  backend_port                   = 8080
  frontend_ip_configuration_name = "PublicIPAddress"
    probe_id                     = azurerm_lb_probe.lbp.id
  backend_address_pool_id       =  azurerm_lb_backend_address_pool.albap.id
}

resource "azurerm_virtual_network_peering" "shay_peering_tobustion" {
  name                         = "shayvnetpe"
  resource_group_name          = azurerm_resource_group.rg.name
  virtual_network_name         = azurerm_virtual_network.vnet.name
  remote_virtual_network_id    = data.azurerm_virtual_network.vnety.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit = false
}
resource "azurerm_virtual_network_peering" "bastion_peering" {
  name                         = "shayvnetper"
  resource_group_name          = data.azurerm_resource_group.rgy.name
  virtual_network_name         = data.azurerm_virtual_network.vnety.name
  remote_virtual_network_id    = azurerm_virtual_network.vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true

  # `allow_gateway_transit` must be set to false for vnet Global Peering
  allow_gateway_transit = false
}

resource "azurerm_lb_probe" "lbp" {
  resource_group_name = azurerm_resource_group.rg.name
  loadbalancer_id     = azurerm_lb.lb.id
  name                = "http-running-probe"
  port                = 8080
}
 resource "azurerm_network_security_group" "nsg" {
   name                = "firewall"
   location            = var.location
   resource_group_name = azurerm_resource_group.rg.name
    security_rule {
     name                       = "port8080"
     priority                   = 100
     direction                  = "Inbound"
     access                     = "Allow"
     protocol                   = "*"
     source_port_range          = "*"
     destination_port_range     = "8080"
     source_address_prefix      = "212.179.161.98/32"
     destination_address_prefix = "*"
   }
    security_rule {
     name                       = "git1"
     priority                   = 101
     direction                  = "Inbound"
     access                     = "Allow"
     protocol                   = "*"
     source_port_range          = "*"
     destination_port_range     = "8080"
     source_address_prefix      = "192.30.252.0/22"
     destination_address_prefix = "*"
 }
    security_rule {
     name                       = "git2"
     priority                   = 102
     direction                  = "Inbound"
     access                     = "Allow"
     protocol                   = "Tcp"
     source_port_range          = "*"
     destination_port_range     = "8080"
     source_address_prefix      = "140.82.112.0/20"
     destination_address_prefix = "*"
 }
    security_rule {
     name                       = "home"
     priority                   = 103
     direction                  = "Inbound"
     access                     = "Allow"
     protocol                   = "Tcp"
     source_port_range          = "*"
     destination_port_range     = "8080"
     source_address_prefix      = "34.99.159.243/32"
     destination_address_prefix = "*"
}
}
 resource "azurerm_network_interface_security_group_association" "nsgg" {
    count = 2
    #default = [element(var.subnet_address, count.index)]
   #count = "${terraform.workspace == "production" ? 2 : 1}"
   # count = 3
   network_interface_id      = azurerm_network_interface.nic[count.index].id
   network_security_group_id = azurerm_network_security_group.nsg.id
    depends_on                = [azurerm_network_security_group.nsg, azurerm_network_interface.nic]
 }
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "shay-keyvault" {
  name                = "shay-keyvault"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "premium"
}

resource "azurerm_key_vault_access_policy" "access" {
  key_vault_id = azurerm_key_vault.shay-keyvault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = "08d0cb9f-26ef-48e1-b1d4-668ce7469220"

  key_permissions = [
    "Get",
  ]

  secret_permissions = [
    "Get",
  ]
}
