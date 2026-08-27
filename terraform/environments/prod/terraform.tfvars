# ─────────────────────────────────────────────────────────────
# Production environment — sample variable values
# Replace all values before applying to a real environment.
# ─────────────────────────────────────────────────────────────

location            = "eastus2"
resource_group_name = "rg-private-aks-prod"
environment         = "prod"

# AKS
aks_node_count = 1
aks_vm_size    = "Standard_D2s_v7"

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
# ~/.ssh/azure_ado_agent_rsa.pub file before applying Terraform.
agent_admin_username       = "azureuser"
agent_admin_ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDDjFZGb0+Ja+BnIgHg7JLNwyVoMtdcy404SIvbm2AWDbvOmXh1tHcAMuKNNw8AzmmxlZCBDiqdNNXlOjOZdYxsN1FBRyW2LcKZBFViIoqzKnkpjzVhdGYg6jJQ9Ql1eQ5a3yEIvITug9BDZbtrQU5zpSUg8wM0cwkJGklZB/EqUsuitxvxHXdKpkxTndpkChcDYXNbs2vMEjPwLxBXeRjtPecWkDBAKF3HRsFHxl3t/wml7JEAZwcHfYTt0kd6a4hKWFnC5xYGRP7NR09O1YYyWaw1ickjXkPpaEytJVjrDUP+DCYkZch7Ir3uvwnvYqMe8W7yjs/RFIUIKbHxHustf477utsFdbZ20g4j0LivuwFnKPHrHhx+GR+m+DQoBaChR/oxmKrnJ0YAFrZbKbXm3wd/f6OgZ3i5s1ePeixXpzzFuvBMA3EISLAmYlB/8m0R1p9W5eyhd8S5zGZw71/pBbkJ/YOhC9Lyej+qGcSt9jxh0fNmTUGAQo8IuFX5j2QCKIq1xX5+7UYOzi6WL+QjxtCTb1TqHlKS4A0vtHzwjatQe+uVNeXbx2wuoCFOv4LxU7C8ZhqmSlJjF38NYn7rGnpVRJn8H/hfz5LZvhK9Cv6oij5PQKjhSVPoM6zTBIyjIlSe7Ii/6MhblpVQ5JxiwlFxVe2YNgW/XFds9RROxQ== azure-ado-agent"
agent_vm_size              = "Standard_D2s_v7"
deploy_azure_devops_agent  = false
