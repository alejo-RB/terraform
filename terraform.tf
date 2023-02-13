# Configure the Azure provider
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

resource "azurerm_resource_group" "test_cloudazure" {
  name     = "Arquitectura-Cloud"
  location = "West US 3"
}

# Red Virtual
resource "azurerm_virtual_network" "test_cloudazure" {
  name                = "network_vm"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.test_cloudazure.location
  resource_group_name = azurerm_resource_group.test_cloudazure.name
}

# SubNet
resource "azurerm_subnet" "test_cloudazure" {
  name                 = "SubNet_private"
  resource_group_name  = azurerm_resource_group.test_cloudazure.name
  virtual_network_name = azurerm_virtual_network.test_cloudazure.name
  address_prefixes     = ["10.0.2.0/24"]
}

# IP Publica
resource "azurerm_public_ip" "test_cloudazure" {
  count               = 2
  name                = "publicIP-${count.index}"
  location            = azurerm_resource_group.test_cloudazure.location
  resource_group_name = azurerm_resource_group.test_cloudazure.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "machinerb${count.index}"
}

# Servidor de Base de Datos
resource "azurerm_mssql_server" "ServerBD" {
  name                         = "serverbd3000"
  location                     = azurerm_resource_group.ArquitecturaCloud.location
  resource_group_name          = azurerm_resource_group.ArquitecturaCloud.name
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = "SQLpassword123!"
}

# Bases de Datos
resource "azurerm_mssql_database" "sql-db" {
  name                 = "SQL-Database"
  server_id            = azurerm_mssql_server.ServerBD.id
  create_mode          = "Default"
}

resource "azurerm_mssql_database" "sql-wordpress" {
  name                 = "Database-Wordpress"
  server_id            = azurerm_mssql_server.ServerBD.id
  create_mode          = "Default"
}

# Interfaz de Red
resource "azurerm_network_interface" "test_cloudazure" {
  count               = 2
  name                = "net${count.index}"
  location            = azurerm_resource_group.test_cloudazure.location
  resource_group_name = azurerm_resource_group.test_cloudazure.name

  ip_configuration {
    name                          = "test_cloudazureConfiguration"
    subnet_id                     = azurerm_subnet.test_cloudazure.id
    private_ip_address_allocation = "static"
    private_ip_address            = cidrhost("10.0.2.0/24", 4 + count.index)
    public_ip_address_id          = azurerm_public_ip.test_cloudazure[count.index].id
  }

}

resource "azurerm_managed_disk" "test_cloudazure" {
  count                = 2
  name                 = "datadisk_existing_${count.index}"
  location             = azurerm_resource_group.test_cloudazure.location
  resource_group_name  = azurerm_resource_group.test_cloudazure.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = "32"
}

resource "azurerm_availability_set" "avset" {
  name                         = "avset"
  location                     = azurerm_resource_group.test_cloudazure.location
  resource_group_name          = azurerm_resource_group.test_cloudazure.name
  platform_fault_domain_count  = 2
  platform_update_domain_count = 2
  managed                      = true
}


# Variable para el directorio de clave privada
variable "private_key_path" {
  type    = string
  default = "C:\\terraform\\keys\\private"
}

resource "azurerm_virtual_machine" "test_cloudazure" {
  count                 = 2
  name                  = "CMS${count.index}"
  location              = azurerm_resource_group.test_cloudazure.location
  availability_set_id   = azurerm_availability_set.avset.id
  resource_group_name   = azurerm_resource_group.test_cloudazure.name
  network_interface_ids = [element(azurerm_network_interface.test_cloudazure.*.id, count.index)]
  vm_size               = "Standard_DS1_v2"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  # delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
  # delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "myosdisk${count.index}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  # Optional data disks
  storage_data_disk {
    name              = "datadisk_new_${count.index}"
    managed_disk_type = "Standard_LRS"
    create_option     = "Empty"
    lun               = 0
    disk_size_gb      = "10"
  }

  storage_data_disk {
    name            = element(azurerm_managed_disk.test_cloudazure.*.name, count.index)
    managed_disk_id = element(azurerm_managed_disk.test_cloudazure.*.id, count.index)
    create_option   = "Attach"
    lun             = 1
    disk_size_gb    = element(azurerm_managed_disk.test_cloudazure.*.disk_size_gb, count.index)
  }

  os_profile {
    computer_name  = "Alejo"
    admin_username = "alejo"
    admin_password = "Alejo2001."
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  # Conexion Clave Privada
  connection {
    type        = "ssh"
    user        = "alejo"
    password    = "Alejo2001."
    private_key = file(var.private_key_path)
    host        = azurerm_network_interface.test_cloudazure.id
  }

  tags = {
    environment = "staging"
  }
}


#crear grupo de seguridad y reglas de firewall

resource "azurerm_network_security_group" "reglas" {
  name                = "ssh_reglas"
  location            = azurerm_resource_group.test_cloudazure.location
  resource_group_name = azurerm_resource_group.test_cloudazure.name

  security_rule {
    name                       = "allow_ssh_sg"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "CMS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

#asociacion de grupo de seguridad con las maquinas virtuales existentes
resource "azurerm_network_interface_security_group_association" "association" {

  count = length(azurerm_network_interface.test_cloudazure)

  network_interface_id      = azurerm_network_interface.test_cloudazure[count.index].id
  network_security_group_id = azurerm_network_security_group.reglas.id
}

#Instalación de docker y docker compose


#Sistema de monitoreo
#Logs por medio de consultas
resource "azurerm_log_analytics_workspace" "test_cloudazure" {

  count = length(azurerm_network_interface.test_cloudazure)

  name                = "example-log-analytics-workspace-${count.index}"
  location            = azurerm_resource_group.test_cloudazure.location
  resource_group_name = azurerm_resource_group.test_cloudazure.name

  sku = "PerGB2018"
}

resource "azurerm_storage_account" "test_cloudazure" {

  count = length(azurerm_network_interface.test_cloudazure)

  name                     = "exampleaccount${count.index}"
  resource_group_name     = azurerm_resource_group.test_cloudazure.name
  location                 = azurerm_resource_group.test_cloudazure.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}



