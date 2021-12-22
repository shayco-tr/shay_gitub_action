locals{
  env_name = (terraform.workspace == "stage") ? "stage" : "prod"
}
#create resource group
resource "azurerm_resource_group" "rg" { 
    name     = "${terraform.workspace}_${var.resource_group_name}"
    location = var.location
}
#Create virtual network
resource "azurerm_virtual_network" "vnet" {
    name = "${terraform.workspace}_${var.resource_group_name}"
    address_space      = var.vnet_address_space
    location            = var.location
    resource_group_name = azurerm_resource_group.rg.name
}

# create availability set
resource "azurerm_availability_set" "avs" {
  name                = "${terraform.workspace}_avs"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
}
# Create subnet
resource "azurerm_subnet" "subnet" {
  name                 =  "${terraform.workspace}" 
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
   address_prefix  = var.subnet
}
# Create network interface
resource "azurerm_network_interface" "nic" {
  name                      = "nic"
  location                  = var.location
  resource_group_name       = azurerm_resource_group.rg.name
ip_configuration {
    name                          = "test"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "dynamic"
    public_ip_address_id = azurerm_public_ip.pi.id
  }
}

# Create virtual machine
resource "azurerm_virtual_machine" "vm" {
  name                  = "shayvmf"
  location              = var.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.nic.id]
  vm_size               = "Standard_DS1_v2"
  availability_set_id   = azurerm_availability_set.avs.id
  storage_os_disk {
    name              = "stvm"
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
      key_data =  data.azurerm_key_vault_secret.PK.value
      path     = "/home/shay/.ssh/authorized_keys"
      #depends_on = [azurerm_key_vault_access_policy.access]
    }
  }
}


data "azurerm_key_vault" "shayKeyVaultn" {
  name                = "shayKeyVaultn"
  resource_group_name = azurerm_resource_group.rg.name
}
data "azurerm_key_vault_secret" "PK" {
  name         = "PK"
  key_vault_id = "${data.azurerm_key_vault.shayKeyVaultn.id}"
}


resource "azurerm_public_ip" "pi" {
  name                = "PublicIPForLB"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
}


 resource "azurerm_network_security_group" "nsg" {
   name                = "firewall"
   location            = var.location
   resource_group_name = azurerm_resource_group.rg.name
    security_rule {
     name                       = "port22"
     priority                   = 100
     direction                  = "Inbound"
     access                     = "Allow"
     protocol                   = "*"
     source_port_range          = "*"
     destination_port_range     = "22"
     source_address_prefixes      = var.whitelist_ips
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
     source_address_prefixes      = var.whitelist_ips
     destination_address_prefix = "*"
}
}
resource "azurerm_virtual_machine_extension" "test" {
   count = var.env == "prod" ? 2 : 1
   name                = "hostname-${count.index}"
   virtual_machine_id   = azurerm_virtual_machine.vm.id
   publisher            = "Microsoft.Azure.Extensions"
   type                 = "CustomScript"
   type_handler_version = "2.0"

   settings = <<SETTINGS
     {
         "commandToExecute":  "cd /home/shay && mkdir ./IaC && sudo apt-get install openjdk-8-jre-headless -y && wget -q -O - https://pkg.jenkins.io/debian-stable/jenkins.io.key | sudo apt-key add - && sudo sh -c 'echo deb http://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list' && sudo apt update -y && sudo apt install jenkins -y"
     }

 SETTINGS

}
 resource "azurerm_network_interface_security_group_association" "nsgg" {
   # count = 2
    #default = [element(var.subnet_address, count.index)]
   #count = "${terraform.workspace == "production" ? 2 : 1}"
   # count = 3
   network_interface_id      = azurerm_network_interface.nic.id
   network_security_group_id = azurerm_network_security_group.nsg.id
    #depends_on                = [azurerm_network_security_group.nsg, azurerm_network_interface.nic]
 }

