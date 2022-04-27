
terraform {

   required_version = ">=0.12"

   required_providers {
     azurerm = {
       source = "hashicorp/azurerm"
       version = "~>2.0"
     }
   }
 }

 provider "azurerm" {
   features {}
 }


#----------------------
#Create Resource Groups
#----------------------
resource "azurerm_resource_group" "production" {
  name     = "production-RG"
  location = "East Asia"
}

resource "azurerm_resource_group" "dr" {
  name     = "dr-RG"
  location = "Australia East"
}

# ----------
# Networking
# ----------

resource "azurerm_virtual_network" "production" {
  name                = "primary-vnet"
  resource_group_name = azurerm_resource_group.production.name
  address_space       = ["10.1.0.0/16"]
  location            = azurerm_resource_group.production.location
}

resource "azurerm_virtual_network" "dr" {
  name                = "dr-vnet"
  resource_group_name = azurerm_resource_group.dr.name
  address_space       = ["10.2.0.0/16"]
  location            = azurerm_resource_group.dr.location
}

resource "azurerm_subnet" "production" {
  name                 = "primary-subnet"
  resource_group_name  = azurerm_resource_group.production.name
  virtual_network_name = azurerm_virtual_network.primary-vnet.name
  address_prefixes     = ["10.1.1.0/24"]
}

resource "azurerm_subnet" "dr" {
  name                 = "dr-subnet"
  resource_group_name  = azurerm_resource_group.dr.name
  virtual_network_name = azurerm_virtual_network.dr-vnet.name
  address_prefixes     = ["10.2.1.0/24"]
}

resource "azurerm_public_ip" "production" {
  name                = "primary-pip"
  allocation_method   = "Static"
  location            = azurerm_resource_group.production.location
  resource_group_name = azurerm_resource_group.production.name
  sku                 = "Basic"
}

resource "azurerm_public_ip" "dr" {
  name                = "secondary-pip"
  allocation_method   = "Static"
  location            = azurerm_resource_group.dr.location
  resource_group_name = azurerm_resource_group.dr.name
  sku                 = "Basic"
}


#----------------------------
#Creating Primary Environment
#----------------------------

resource "azurerm_virtual_machine" "vm" {
  name                  = "vm"
  location              = azurerm_resource_group.production.location
  resource_group_name   = azurerm_resource_group.production.name
  vm_size               = "Standard_D2s_v3"
  network_interface_ids = [azurerm_network_interface.vm.id]

  storage_image_reference {              # Provide OS preferences
    publisher = "Canonical"     
    offer     = "UbuntuServer"
    sku       = "20.04-LTS"
    version   = "latest"
  }

  storage_os_disk {                     # Disk preferences
    name              = "vm-os-disk" 
    os_type           = "Linux"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {                          # Login Credentials
    admin_username = "admin"  
    admin_password = "pa$$word"
    computer_name  = "vm"
  }

  os_profile_linux_config {                     
    disable_password_authentication = false
  }
}

#-----------------------
# Creatiion of ASR Vault
#-----------------------

resource "azurerm_recovery_services_vault" "ASR-vault" {
  name                = "Site-Recovery-Vault"
  location            = azurerm_resource_group.dr.location
  resource_group_name = azurerm_resource_group.dr.name
  sku                 = "Standard"
}

resource "azurerm_site_recovery_fabric" "primary" {
  name                = "primary-fabric"
  resource_group_name = azurerm_resource_group.secondary.name
  recovery_vault_name = azurerm_recovery_services_vault.vault.name
  location            = azurerm_resource_group.primary.location
}

resource "azurerm_site_recovery_fabric" "secondary" {
  name                = "secondary-fabric"
  resource_group_name = azurerm_resource_group.secondary.name
  recovery_vault_name = azurerm_recovery_services_vault.vault.name
  location            = azurerm_resource_group.secondary.location
}

resource "azurerm_site_recovery_protection_container" "primary" {
  name                 = "primary-protection-container"
  resource_group_name  = azurerm_resource_group.secondary.name
  recovery_vault_name  = azurerm_recovery_services_vault.vault.name
  recovery_fabric_name = azurerm_site_recovery_fabric.primary.name
}

resource "azurerm_site_recovery_protection_container" "secondary" {
  name                 = "secondary-protection-container"
  resource_group_name  = azurerm_resource_group.secondary.name
  recovery_vault_name  = azurerm_recovery_services_vault.vault.name
  recovery_fabric_name = azurerm_site_recovery_fabric.secondary.name
}

resource "azurerm_site_recovery_replication_policy" "policy" {
  name                                                 = "policy"
  resource_group_name                                  = azurerm_resource_group.secondary.name
  recovery_vault_name                                  = azurerm_recovery_services_vault.vault.name
  recovery_point_retention_in_minutes                  = 24 * 60
  application_consistent_snapshot_frequency_in_minutes = 4 * 60
}

resource "azurerm_site_recovery_protection_container_mapping" "container-mapping" {
  name                                      = "container-mapping"
  resource_group_name                       = azurerm_resource_group.secondary.name
  recovery_vault_name                       = azurerm_recovery_services_vault.vault.name
  recovery_fabric_name                      = azurerm_site_recovery_fabric.primary.name
  recovery_source_protection_container_name = azurerm_site_recovery_protection_container.primary.name
  recovery_target_protection_container_id   = azurerm_site_recovery_protection_container.secondary.id
  recovery_replication_policy_id            = azurerm_site_recovery_replication_policy.policy.id
}

resource "azurerm_site_recovery_network_mapping" "network-mapping" {
  name                        = "network-mapping"
  resource_group_name         = azurerm_resource_group.secondary.name
  recovery_vault_name         = azurerm_recovery_services_vault.vault.name
  source_recovery_fabric_name = azurerm_site_recovery_fabric.primary.name
  target_recovery_fabric_name = azurerm_site_recovery_fabric.secondary.name
  source_network_id           = azurerm_virtual_network.primary.id
  target_network_id           = azurerm_virtual_network.secondary.id
}

#------------------------------------------
# Primary Site Storage Accounts  - Optional
#------------------------------------------
resource "azurerm_storage_account" "primary" {
  name                     = "primaryrecoverycache"
  location                 = azurerm_resource_group.primary.location
  resource_group_name      = azurerm_resource_group.primary.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
}



resource "azurerm_network_interface" "vm" {
  name                = "vm-nic"
  location            = azurerm_resource_group.primary.location
  resource_group_name = azurerm_resource_group.primary.name

  ip_configuration {
    name                          = "vm"
    subnet_id                     = azurerm_subnet.primary.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.primary.id
  }
}

# -----------
# Replication
# -----------

resource "azurerm_site_recovery_replicated_vm" "vm-replication" {
  name                                      = "vm-replication"
  resource_group_name                       = azurerm_resource_group.dr.name
  recovery_vault_name                       = azurerm_recovery_services_vault.ASR-vault.name
  source_recovery_fabric_name               = azurerm_site_recovery_fabric.primary.name
  source_vm_id                              = azurerm_virtual_machine.vm.id
  recovery_replication_policy_id            = azurerm_site_recovery_replication_policy.policy.id
  source_recovery_protection_container_name = azurerm_site_recovery_protection_container.primary.name

  target_resource_group_id                = azurerm_resource_group.secondary.id
  target_recovery_fabric_id               = azurerm_site_recovery_fabric.secondary.id
  target_recovery_protection_container_id = azurerm_site_recovery_protection_container.secondary.id

  managed_disk {
    disk_id                    = azurerm_virtual_machine.vm.storage_os_disk[0].managed_disk_id
    staging_storage_account_id = azurerm_storage_account.primary.id
    target_resource_group_id   = azurerm_resource_group.secondary.id
    target_disk_type           = "Premium_LRS"
    target_replica_disk_type   = "Premium_LRS"
  }

  network_interface {
    source_network_interface_id   = azurerm_network_interface.vm.id
    target_subnet_name            = azurerm_subnet.dr.name
    recovery_public_ip_address_id = azurerm_public_ip.dr.id
  }

  depends_on = [
    azurerm_site_recovery_protection_container_mapping.container-mapping,
    azurerm_site_recovery_network_mapping.network-mapping,
  ]
}