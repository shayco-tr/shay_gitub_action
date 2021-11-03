 variable "resource_group_name" {
    type = string
    description = "Name of the system or environment"
    default = "shayvm"
}
variable "subnet" {
    type = list(any)
    default = ["29.0.0.0/24", "29.0.1.0/24"] 
}
variable "servername" {
    type = string
    description = "Server name of the virtual machine"
    default = "shayvm"
}

variable "location" {
    type = string
    description = "Azure location of terraform server environment"
    default = "eastus"

}

variable "admin_username" {
    type = string
    description = "Administrator username for server"
    default = "shay"
}
variable "vnet_name" {
    type = string
    description = "Administrator username for server"
    default = "shaymyt"
}

#variable "admin_password" {
#    type = string
#    description = "Administrator password for server"
#}

variable "vnet_address_space" { 
    type = list
    description = "Address space for Virtual Network"
    default = ["29.0.0.0/16"]
}

variable "managed_disk_type" { 
    type = map
    description = "Disk type Premium in Primary location Standard in DR location"

    default = {
        westus2 = "Premium_LRS"
        eastus = "Standard_LRS"
    }
}

variable "vm_size" {
    type = string
    description = "Size of VM"
    default = "Standard_B1s"
}

variable "os" {
    description = "OS image to deploy"
    type = object({
        publisher = string
        offer = string
        sku = string
        version = string
  })
}      
variable "prefix" {
  type = string
  default = "shaytf"
}
variable "env" {
  type = string
}