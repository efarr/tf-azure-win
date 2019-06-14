locals {
  vm_count  = 2
  location  = "centralus"
  envtag    = "Terraform Demo"
}

provider "azurerm" {
    subscription_id = "${var.subscription_id}"
    client_id 		= "${var.client_id}"
    client_secret 	= "${var.client_secret}"
    tenant_id 		= "${var.tenant_id}"
}

variable "subscription_id" {
  description = "Enter Subscription ID for provisioning resources in Azure"
}

variable "client_id" {
  description = "Enter Client ID for Application created in Azure AD"
}

variable "client_secret" {
  description = "Enter Client secret for Application in Azure AD"
}

variable "tenant_id" {
  description = "Enter Tenant ID / Directory ID of your Azure AD. Run Get-AzureSubscription to know your Tenant ID"
}

variable "admin_password" {
  description = "Windows V2Admin password"
}

resource "azurerm_resource_group" "tf_demo_group" {
    name     = "tf-demo-rg"
    location = "${local.location}"

    tags {
        environment = "${local.envtag}"
    }
}

resource "azurerm_virtual_network" "tf_demo_network" {
    name                = "demoVnet"
    address_space       = ["10.0.0.0/16"]
    location            = "${local.location}"
    resource_group_name = "${azurerm_resource_group.tf_demo_group.name}"

    tags {
        environment = "${local.envtag}"
    }
}

resource "azurerm_subnet" "tf_demo_subnet" {
    name                 = "demoSubnet"
    resource_group_name  = "${azurerm_resource_group.tf_demo_group.name}"
    virtual_network_name = "${azurerm_virtual_network.tf_demo_network.name}"
    address_prefix       = "10.0.2.0/24"
}

resource "azurerm_public_ip" "tf_demo_publicip" {
    count                        = "${local.vm_count}"
    name                         = "demoPublicIP${count.index}"
    location                     = "${local.location}"
    resource_group_name          = "${azurerm_resource_group.tf_demo_group.name}"
    public_ip_address_allocation = "dynamic"

    tags {
        environment = "${local.envtag}"
    }
}

resource "azurerm_network_security_group" "tf_demo_nsg" {
    name                = "demoNetworkSecurityGroup"
    location            = "${local.location}"
    resource_group_name = "${azurerm_resource_group.tf_demo_group.name}"

    security_rule {
        name                       = "RDP"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "3389"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    tags {
        environment = "${local.envtag}"
    }
}

resource "azurerm_network_interface" "tf_demo_nic" {
    count                 = "${local.vm_count}"
    name                = "demoNIC${count.index}"
    location            = "${local.location}"
    resource_group_name = "${azurerm_resource_group.tf_demo_group.name}"

    ip_configuration {
        name                          = "demoNicConfiguration"
        subnet_id                     = "${azurerm_subnet.tf_demo_subnet.id}"
        private_ip_address_allocation = "dynamic"
        public_ip_address_id          = "${element(azurerm_public_ip.tf_demo_publicip.*.id, count.index)}"
    }

    tags {
        environment = "${local.envtag}"
    }
}

resource "random_id" "randomId" {
    keepers = {
        resource_group_name = "${azurerm_resource_group.tf_demo_group.name}"
    }

    byte_length = 8
}

resource "azurerm_storage_account" "tf_demo_storageaccount" {
    name                = "diag${random_id.randomId.hex}"
    resource_group_name = "${azurerm_resource_group.tf_demo_group.name}"
    location            = "${local.location}"
    account_replication_type = "LRS"
    account_tier = "Standard"

    tags {
        environment = "${local.envtag}"
    }
}

resource "azurerm_storage_container" "cont1" {
  name                  = "vhds"
  resource_group_name   = "${azurerm_resource_group.tf_demo_group.name}"
  storage_account_name  = "${azurerm_storage_account.tf_demo_storageaccount.name}"
  container_access_type = "private"
}

resource "azurerm_virtual_machine" "tf_demo_vm" {
    count                 = "${local.vm_count}"
    name                  = "tfVM${count.index}"
    location              = "${local.location}"
    resource_group_name   = "${azurerm_resource_group.tf_demo_group.name}"
    network_interface_ids = ["${element(azurerm_network_interface.tf_demo_nic.*.id, count.index)}"]
    vm_size               = "Standard_B2s"

    storage_os_disk {
        name          = "osdisk${count.index}"
        vhd_uri       = "${azurerm_storage_account.tf_demo_storageaccount.primary_blob_endpoint}${azurerm_storage_container.cont1.name}/osdisk${count.index}.vhd"
        caching       = "ReadWrite"
        create_option = "FromImage"
        disk_size_gb      = "512"
    }

    storage_data_disk {
        name          = "datadisk${count.index}"
        vhd_uri       = "${azurerm_storage_account.tf_demo_storageaccount.primary_blob_endpoint}${azurerm_storage_container.cont1.name}/datadisk${count.index}.vhd"
        disk_size_gb  = "60"
        create_option = "Empty"
        lun           = 0
    }

    storage_image_reference {
        publisher = "MicrosoftWindowsServer"
        offer     = "WindowsServer"
        sku       = "2016-Datacenter"
        version   = "latest"
    }

    os_profile {
        computer_name  = "testvm${count.index}"
        admin_username = "V2Admin"
        admin_password = "${var.admin_password}"
    }

    os_profile_windows_config {
        enable_automatic_upgrades = "true"
    }

    boot_diagnostics {
        enabled     = "true"
        storage_uri = "${azurerm_storage_account.tf_demo_storageaccount.primary_blob_endpoint}"
    }

    tags {
        environment = "${local.envtag}"
    }
}