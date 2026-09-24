variable "subscription_id" {
  type        = string
  description = "Azure subscription ID (set in terraform.tfvars)"
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

variable "n" {
  type        = number
  description = "Number of Azure worker nodes"
  default     = 1
}

resource "azurerm_resource_group" "k8s_rg" {
  name     = "k8sResourceGroup"
  location = "North Central US"

  tags = {
    environment = "K8s Resource Group"
  }
}

resource "azurerm_virtual_network" "k8s_vnet" {
  name                = "k8sVnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.k8s_rg.location
  resource_group_name = azurerm_resource_group.k8s_rg.name

  tags = {
    environment = "K8s VN"
  }
}

resource "azurerm_subnet" "k8s_subnet" {
  name                 = "k8sSubnet"
  resource_group_name  = azurerm_resource_group.k8s_rg.name
  virtual_network_name = azurerm_virtual_network.k8s_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "k8s_nsg" {
  name                = "k8sNetworkSecurityGroup"
  location            = azurerm_resource_group.k8s_rg.location
  resource_group_name = azurerm_resource_group.k8s_rg.name

  security_rule {
    name                       = "AllowAll"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "K8s Security Group"
  }
}

# --- Control Plane (Master) ---

resource "azurerm_public_ip" "master_ip" {
  name                = "k8sMasterPublicIP"
  location            = azurerm_resource_group.k8s_rg.location
  resource_group_name = azurerm_resource_group.k8s_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    environment = "K8s Master IP"
  }
}

resource "azurerm_network_interface" "master_nic" {
  name                = "k8sMasterNIC"
  location            = azurerm_resource_group.k8s_rg.location
  resource_group_name = azurerm_resource_group.k8s_rg.name

  ip_configuration {
    name                          = "masterNicConfig"
    subnet_id                     = azurerm_subnet.k8s_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.master_ip.id
  }

  tags = {
    environment = "K8s Master NIC"
  }
}

resource "azurerm_network_interface_security_group_association" "master_sga" {
  network_interface_id      = azurerm_network_interface.master_nic.id
  network_security_group_id = azurerm_network_security_group.k8s_nsg.id
}

resource "azurerm_linux_virtual_machine" "master" {
  name                  = "k8s-master"
  location              = azurerm_resource_group.k8s_rg.location
  resource_group_name   = azurerm_resource_group.k8s_rg.name
  network_interface_ids = [azurerm_network_interface.master_nic.id]
  size                  = "Standard_D2s_v3"

  os_disk {
    name                 = "masterOsDisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  computer_name                   = "k8s-master"
  admin_username                  = "ubuntu"
  disable_password_authentication = true

  admin_ssh_key {
    username   = "ubuntu"
    public_key = tls_private_key.k8s_ssh.public_key_openssh
  }

  tags = {
    environment = "Control Plane"
  }
}

# --- Worker Nodes (Azure) ---

resource "azurerm_public_ip" "worker_ip" {
  count               = var.n
  name                = "k8sWorkerPublicIP${count.index}"
  location            = azurerm_resource_group.k8s_rg.location
  resource_group_name = azurerm_resource_group.k8s_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    environment = "K8s Worker IP"
  }
}

resource "azurerm_network_interface" "worker_nic" {
  count               = var.n
  name                = "k8sWorkerNIC${count.index}"
  location            = azurerm_resource_group.k8s_rg.location
  resource_group_name = azurerm_resource_group.k8s_rg.name

  ip_configuration {
    name                          = "workerNicConfig${count.index}"
    subnet_id                     = azurerm_subnet.k8s_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.worker_ip[count.index].id
  }

  tags = {
    environment = "K8s Worker NIC"
  }
}

resource "azurerm_network_interface_security_group_association" "worker_sga" {
  count                     = var.n
  network_interface_id      = azurerm_network_interface.worker_nic[count.index].id
  network_security_group_id = azurerm_network_security_group.k8s_nsg.id
}

resource "azurerm_linux_virtual_machine" "worker" {
  count                 = var.n
  name                  = "k8s-worker-${count.index}"
  location              = azurerm_resource_group.k8s_rg.location
  resource_group_name   = azurerm_resource_group.k8s_rg.name
  network_interface_ids = [azurerm_network_interface.worker_nic[count.index].id]
  size                  = "Standard_D2s_v3"

  os_disk {
    name                 = "workerOsDisk${count.index}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  computer_name                   = "k8s-worker-${count.index}"
  admin_username                  = "ubuntu"
  disable_password_authentication = true

  admin_ssh_key {
    username   = "ubuntu"
    public_key = tls_private_key.k8s_ssh.public_key_openssh
  }

  tags = {
    environment = "Worker Node ${count.index + 1}"
  }
}
