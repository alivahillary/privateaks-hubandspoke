data "azurerm_firewall" "fw" {
  name                = "kubenetfw"
  resource_group_name = var.resource_group
}

resource "azurerm_public_ip" "pip" {
  name                = "vm-pip"
  location            = var.location
  resource_group_name = var.resource_group
  allocation_method   = "Static"
}

resource "azurerm_network_security_group" "jumpbox" {
  name                = "jumpbox-nsg"
  location            = var.location
  resource_group_name = var.resource_group

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowKubeAPI"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowKubeNodePort"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "30000-32767"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
resource "azurerm_network_security_rule" "allow_firewall_to_aks" {
  name                        = "Allow-Firewall-to-AKS"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  
  // Use the firewall's subnet CIDR or specific private IP.
  // For example, if your firewall is in a dedicated subnet "10.1.0.0/24":
  # source_address_prefix       = "10.1.0.0/24"
  
  // Alternatively, if you want to allow traffic from the specific firewall private IP:
  source_address_prefix     = data.azurerm_firewall.fw.ip_configuration[0].private_ip_address
  source_port_range          = "*"
  destination_address_prefix  = "*"
  destination_port_range      = "8080"
  resource_group_name         = var.resource_group
  network_security_group_name = azurerm_network_security_group.jumpbox.name
}

resource "azurerm_network_security_rule" "allow_outbound_docker" {
  name                        = "allow-outbound-docker"
  priority                    = 150
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range          = "*" // Allow all source ports
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  destination_port_range      = "443"
  resource_group_name         = var.resource_group
  network_security_group_name = azurerm_network_security_group.jumpbox.name
}

resource "azurerm_network_interface" "jumpbox" {
  name                = "jumpbox-nic"
  location            = var.location
  resource_group_name = var.resource_group

  ip_configuration {
    name                          = "jumpbox-nicConfig"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "sg_association" {
  network_interface_id      = azurerm_network_interface.jumpbox.id
  network_security_group_id = azurerm_network_security_group.jumpbox.id
}

resource "azurerm_linux_virtual_machine" "jumpbox" {
  name                            = "jumpboxvm"
  location                        = var.location
  resource_group_name             = var.resource_group
  network_interface_ids           = [azurerm_network_interface.jumpbox.id]
  size                            = "Standard_DS1_v2"
  computer_name                   = "jumpboxvm"
  admin_username                  = var.vm_user
  admin_password                  = var.passwd
  disable_password_authentication = false

  os_disk {
    name                 = "jumpboxOsDisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "19_10-daily-gen2"
    version   = "latest"
  }

  provisioner "remote-exec" {
    connection {
      host     = self.public_ip_address
      type     = "ssh"
      user     = var.vm_user
      password = var.passwd
    }

    inline = [
      # Install kubectl
      "curl -LO https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl",

      "curl -LO https://dl.k8s.io/release/$(curl -L -s     https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256",

      "echo $(cat kubectl.sha256)  kubectl | sha256sum --check",

      "sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl",

      "kubectl version --client --output=yaml",

      #Install azcli
      "sudo apt-get update",

      "sudo apt-get install apt-transport-https ca-certificates curl gnupg lsb-release",

      #Microsoft Signing Key
      "sudo mkdir -p /etc/apt/keyrings",

      "curl -sLS https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/keyrings/microsoft.gpg > /dev/null",

      "sudo chmod go+r /etc/apt/keyrings/microsoft.gpg",

      #Add Azure CLI Repository
      "echo \"deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main\" | sudo tee /etc/apt/sources.list.d/azure-cli.list",

      "sudo apt-get update",

      "sudo apt-get install azure-cli"


    # # Update package list
    # "sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gpg",

    # # Remove any old Kubernetes repo and add the new one
    # "sudo rm -f /etc/apt/sources.list.d/kubernetes.list",
    # "curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.27/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg",
    # "echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.27/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list",

    # # Update apt and install kubectl
    # "sudo apt-get update",
    # "sudo apt-get install -y kubectl",

    # # Install Azure CLI
    # "curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
   ]
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "hublink" {
  name                  = "hubnetdnsconfig"
  resource_group_name   = var.dns_zone_resource_group
  private_dns_zone_name = var.dns_zone_name
  virtual_network_id    = var.vnet_id
}