# ─────────────────────────────────────────────────────────────
# Production environment — sample variable values
# Replace all values before applying to a real environment.
# ─────────────────────────────────────────────────────────────

location            = "eastus2"
resource_group_name = "rg-private-aks-prod"
environment         = "prod"

# AKS
aks_node_count = 3
aks_vm_size    = "Standard_D4ds_v5"

# ACR — must be globally unique, alphanumeric only
acr_name = "acrprivaksprod001"

# Key Vault — must be globally unique, 3-24 chars
keyvault_name = "kv-priv-aks-prod-001"

# Networking
vnet_address_space = "10.0.0.0/8"
aks_subnet_cidr    = "10.1.0.0/16"
pe_subnet_cidr     = "10.2.0.0/24"
agent_subnet_cidr  = "10.3.0.0/24"

# Agent VM: replace the placeholder with the contents of your local
# ~/.ssh/id_ed25519.pub file before applying Terraform.
agent_admin_username       = "azureuser"
agent_admin_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEcSwNNJcWTiT/bqSg+bWtfW9f9a6AIsQgVBu5I4HA4P azure-ado-agent"
agent_vm_size              = "Standard_B2s"
