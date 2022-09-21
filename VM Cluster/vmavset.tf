# VM Availability Set deployment
terraform {

  required_version = ">=0.12"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "redun_set" {
  name     = "redundantrg"
  location = "Southeast Asia"
}

resource "azurerm_virtual_network" "redun_vnet" {
  name                = "redundantvnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.redun_set.location
  resource_group_name = azurerm_resource_group.redun_set.name
}

resource "azurerm_subnet" "redun_snet" {
  name                 = "redundantsnet"
  resource_group_name  = azurerm_resource_group.redun_set.name
  virtual_network_name = azurerm_virtual_network.redun_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "pip" {
  name                = "PIPforNLB"
  location            = azurerm_resource_group.redun_set.location
  resource_group_name = azurerm_resource_group.redun_set.name
  allocation_method   = "Static"
}
#======================================
# Change details to amend LB Values
#======================================
resource "azurerm_lb" "NLB" {
  name                = "NLB"
  location            = azurerm_resource_group.redun_set.location
  resource_group_name = azurerm_resource_group.redun_set.name
  sku                 = "Basic"

  frontend_ip_configuration {
    name                 = "NLBfrontPIP"
    public_ip_address_id = azurerm_public_ip.pip.id
  }
}

resource "azurerm_lb_backend_address_pool" "BackIP" {
  loadbalancer_id = azurerm_lb.NLB.id
  name            = "BackEndAddressPool"
}

resource "azurerm_network_interface" "nic" {
  count               = 2
  name                = "vnic${count.index}"
  location            = azurerm_resource_group.redun_set.location
  resource_group_name = azurerm_resource_group.redun_set.name

  ip_configuration {
    name                          = "BaseConfig"
    subnet_id                     = azurerm_subnet.redun_snet.id
    private_ip_address_allocation = "dynamic"
  }
}
resource "azurerm_managed_disk" "mdisk" {
  count                = 2
  name                 = "datadisk_existing_${count.index}"
  location             = azurerm_resource_group.redun_set.location
  resource_group_name  = azurerm_resource_group.redun_set.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = "20"
}

resource "azurerm_availability_set" "avset" {
  name                         = "avset"
  location                     = azurerm_resource_group.redun_set.location
  resource_group_name          = azurerm_resource_group.redun_set.name
  platform_fault_domain_count  = 2
  platform_update_domain_count = 5
  managed                      = true
}


#==================================================
#change this resource as per required VM parameters
#==================================================

resource "azurerm_virtual_machine" "VM" {
  count                 = 2
  name                  = "VM${count.index}"
  location              = azurerm_resource_group.redun_set.location
  availability_set_id   = azurerm_availability_set.avset.id
  resource_group_name   = azurerm_resource_group.redun_set.name
  network_interface_ids = [element(azurerm_network_interface.nic.*.id, count.index)]
  vm_size               = "Standard_DS1_v2"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "20.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "myosdisk${count.index}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  # Optional data disks
  #storage_data_disk {
  # name              = "datadisk_new_${count.index}"
  #managed_disk_type = "Standard_LRS"
  #create_option     = "Empty"
  #lun               = 0
  #disk_size_gb      = "1023"
  #}

  #storage_data_disk {
  #name            = element(azurerm_managed_disk.mdisk.*.name, count.index)
  #managed_disk_id = element(azurerm_managed_disk.mdisk.*.id, count.index)
  #create_option   = "Attach"
  #lun             = 1
  #disk_size_gb    = element(azurerm_managed_disk.mdisk.*.disk_size_gb, count.index)
  #}
  #===================================================
  # Change here according to requirements of OS logins
  #===================================================

  os_profile {
    computer_name  = "hostname"
    admin_username = "admin"
    admin_password = "admin123"
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  tags = {
    environment = "basic_avset_vm_template"
  }
}