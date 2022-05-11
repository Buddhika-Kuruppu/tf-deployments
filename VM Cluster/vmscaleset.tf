#-----------------------------------------------------
#create VM scale set with LB for VM with Managed Disks
#-----------------------------------------------------

resource "azurerm_resource_group" "prodrg" {
  name     = "all-resources"
  location = "South India"
}

resource "azurerm_virtual_network" "prodvnet" {
  name                = "vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.prodrg.location
  resource_group_name = azurerm_resource_group.prodrg.name
}

resource "azurerm_subnet" "prodsnet" {
  name                 = "acctsub"
  resource_group_name  = azurerm_resource_group.prodrg.name
  virtual_network_name = azurerm_virtual_network.prodvnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "prodpip" {
  name                = "pip"
  location            = azurerm_resource_group.prodrg.location
  resource_group_name = azurerm_resource_group.prodrg.name
  allocation_method   = "Static"
  domain_name_label   = azurerm_resource_group.prodrg.name

  tags = {
    environment = "development"
    Purpose = "Base Template"
  }
}

resource "azurerm_lb" "prodlb" {
  name                = "ELB"
  location            = azurerm_resource_group.prodrg.location
  resource_group_name = azurerm_resource_group.prodrg.name

  frontend_ip_configuration {
    name                 = "PublicIPEnd"
    public_ip_address_id = azurerm_public_ip.prodpip.id
  }
}

resource "azurerm_lb_backend_address_pool" "backendpool" {
  resource_group_name = azurerm_resource_group.prodrg.name
  loadbalancer_id     = azurerm_lb.prodlb.id
  name                = "BackendIPPool"
}

#Completed up to here above

resource "azurerm_lb_nat_pool" "lbnatpool" {
  resource_group_name            = azurerm_resource_group.prodrg.name
  name                           = "for_secure_access"
  loadbalancer_id                = azurerm_lb.prodlb.id
  protocol                       = "TCP"
  frontend_port_start            = 1
  frontend_port_end              = 60000
  backend_port                   = 22
  frontend_ip_configuration_name = "PIPAddress"
}

resource "azurerm_lb_probe" "lbprobe" {
  resource_group_name = azurerm_resource_group.prodrg.name
  loadbalancer_id     = azurerm_lb.prodlb.id
  name                = "http-probe"
  protocol            = "Http"
  request_path        = "/health"
  port                = 8080
}
#------------------------------------
# Defining Azure Scale Set parameters
#------------------------------------

resource "azurerm_virtual_machine_scale_set" "vmscset" {
  name                = "webserver-scset"
  location            = azurerm_resource_group.prodrg.location
  resource_group_name = azurerm_resource_group.prodrg.name

  # automatic rolling upgrade
  automatic_os_upgrade = true
  upgrade_policy_mode  = "Rolling"

  rolling_upgrade_policy {
    max_batch_instance_percent              = 20
    max_unhealthy_instance_percent          = 20
    max_unhealthy_upgraded_instance_percent = 5
    pause_time_between_batches              = "PT0S"
  }

  # required when using rolling upgrade policy
  health_probe_id = azurerm_lb_probe.lbprobe.id

  sku {
    name     = "Standard_D2s_v3"
    tier     = "Standard"
    capacity = 2
  }

  storage_profile_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_profile_os_disk {
    name              = "os-disk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_profile_data_disk {
    lun           = 0
    caching       = "ReadWrite"
    create_option = "Empty"
    disk_size_gb  = 10
  }

  os_profile {
    computer_name_prefix = "WEB"
    admin_username       = "webadmin"
    admin_password       = "testpassword"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path     = "/home/webadmin/.ssh/authorized_keys"
      key_data = file("~/.ssh/demo_key.pub")
    }
  }

  network_profile {
    name    = "terraformnetworkprofile"
    primary = true

    ip_configuration {
      name                                   = "ScSetIPConfiguration"
      primary                                = true
      subnet_id                              = azurerm_subnet.prodsnet.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.backendpool.id]
      load_balancer_inbound_nat_rules_ids    = [azurerm_lb_nat_pool.lbnatpool.id]
    }
  }

  tags = {
    environment = "Development"
  }
}

#---------------------------
# Auto Scaling Configuration
#---------------------------

resource "azurerm_monitor_autoscale_setting" "asconfig" {
  name                = "AutoscaleConfig"
  resource_group_name = azurerm_resource_group.prodrg.name
  location            = azurerm_resource_group.prodrg.location
  target_resource_id  = azurerm_virtual_machine_scale_set.vmscset.id

# parameters for Auto-Scaling

  profile {
    name = "defaultProfile"

    capacity {
      default = 1
      minimum = 1
      maximum = 5
    }

# Load Increasing Rule 

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_virtual_machine_scale_set.vmscset.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 75
        metric_namespace   = "microsoft.compute/virtualmachinescalesets"
        dimensions {
          name     = "AppName"
          operator = "Equals"
          values   = ["App1"]
        }
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }

# Load Decreasing Rule

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_virtual_machine_scale_set.vmscset.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }
  }

  notification {
    email {
      send_to_subscription_administrator    = true
      send_to_subscription_co_administrator = true
      custom_emails                         = ["buddhikakuruppu@hotmail.com"]
    }
  }
}