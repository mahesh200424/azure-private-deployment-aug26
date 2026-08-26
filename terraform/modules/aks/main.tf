# ─────────────────────────────────────────────────────────────
# Module: aks
# Creates: Private AKS cluster, system + user node pools,
#          kubelet managed identity, AcrPull role assignment,
#          Private DNS Zone, workload identity / OIDC issuer,
#          Azure CNI networking, Key Vault CSI driver addon
# ─────────────────────────────────────────────────────────────

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

locals {
  name_prefix  = "${var.environment}-private"
  cluster_name = "aks-${local.name_prefix}"

  common_tags = {
    environment = var.environment
    managed_by  = "terraform"
    module      = "aks"
  }
}

# ─────────────────────────────────────────────────────────────
# User-assigned managed identity for the AKS control plane
# ─────────────────────────────────────────────────────────────
resource "azurerm_user_assigned_identity" "aks_control_plane" {
  name                = "mi-aks-cp-${local.name_prefix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = local.common_tags
}

# ─────────────────────────────────────────────────────────────
# User-assigned managed identity for AKS kubelet
# (used to pull images from ACR and read Key Vault secrets)
# ─────────────────────────────────────────────────────────────
resource "azurerm_user_assigned_identity" "aks_kubelet" {
  name                = "mi-aks-kubelet-${local.name_prefix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = local.common_tags
}

# ─────────────────────────────────────────────────────────────
# Private DNS Zone for AKS API server
# ─────────────────────────────────────────────────────────────
resource "azurerm_private_dns_zone" "aks" {
  name                = "privatelink.${var.location}.azmk8s.io"
  resource_group_name = var.resource_group_name
  tags                = local.common_tags
}

# Grant AKS control-plane identity contributor on the private DNS zone
# so it can manage A records for the API server endpoint.
resource "azurerm_role_assignment" "aks_dns_contributor" {
  scope                = azurerm_private_dns_zone.aks.id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_control_plane.principal_id
}

# Grant AKS control-plane identity network contributor on the VNet
# (required for Azure CNI to allocate IPs from the subnet).
resource "azurerm_role_assignment" "aks_network_contributor" {
  scope                = var.aks_subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_control_plane.principal_id
}

# ─────────────────────────────────────────────────────────────
# AcrPull role assignment for kubelet identity
# ─────────────────────────────────────────────────────────────
resource "azurerm_role_assignment" "kubelet_acrpull" {
  scope                            = var.acr_id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_user_assigned_identity.aks_kubelet.principal_id
  skip_service_principal_aad_check = true
}

# ─────────────────────────────────────────────────────────────
# AKS Cluster
# ─────────────────────────────────────────────────────────────
resource "azurerm_kubernetes_cluster" "main" {
  name                       = local.cluster_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  dns_prefix_private_cluster = var.dns_prefix
  kubernetes_version         = var.kubernetes_version
  node_resource_group        = "rg-${local.cluster_name}-nodes"

  # ── Private cluster ──────────────────────────────────────
  private_cluster_enabled             = true
  private_dns_zone_id                 = azurerm_private_dns_zone.aks.id
  private_cluster_public_fqdn_enabled = false

  # ── Identity ─────────────────────────────────────────────
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks_control_plane.id]
  }

  kubelet_identity {
    client_id                 = azurerm_user_assigned_identity.aks_kubelet.client_id
    object_id                 = azurerm_user_assigned_identity.aks_kubelet.principal_id
    user_assigned_identity_id = azurerm_user_assigned_identity.aks_kubelet.id
  }

  # ── Workload Identity & OIDC ─────────────────────────────
  workload_identity_enabled = true
  oidc_issuer_enabled       = true

  # ── System node pool ─────────────────────────────────────
  default_node_pool {
    name                         = "system"
    node_count                   = var.node_count
    vm_size                      = var.vm_size
    vnet_subnet_id               = var.aks_subnet_id
    os_disk_size_gb              = 128
    os_disk_type                 = "Ephemeral"
    type                         = "VirtualMachineScaleSets"
    zones                        = ["1", "2", "3"]
    only_critical_addons_enabled = true
    enable_auto_scaling          = true
    min_count                    = var.node_count
    max_count                    = var.node_count * 3
    max_pods                     = 110

    node_labels = {
      "nodepool-type" = "system"
      "environment"   = var.environment
    }

    upgrade_settings {
      max_surge = "33%"
    }
  }

  # ── Azure CNI networking ─────────────────────────────────
  network_profile {
    network_plugin    = "azure"
    network_policy    = "calico"
    load_balancer_sku = "standard"
    outbound_type     = "userAssignedNATGateway"
    service_cidr      = "172.16.0.0/16"
    dns_service_ip    = "172.16.0.10"
  }

  # ── Azure Monitor / Insights ─────────────────────────────
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.aks.id
  }

  # ── Key Vault Secrets Store CSI driver ───────────────────
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  # ── Azure AD / RBAC ──────────────────────────────────────
  azure_active_directory_role_based_access_control {
    managed            = true
    azure_rbac_enabled = true
  }

  # ── Auto-upgrade ─────────────────────────────────────────
  automatic_channel_upgrade = "patch"

  maintenance_window {
    allowed {
      day   = "Sunday"
      hours = [1, 2]
    }
  }

  tags = local.common_tags

  depends_on = [
    azurerm_role_assignment.aks_dns_contributor,
    azurerm_role_assignment.aks_network_contributor,
    azurerm_role_assignment.kubelet_acrpull,
  ]
}

# ─────────────────────────────────────────────────────────────
# User node pool — for application workloads
# ─────────────────────────────────────────────────────────────
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.vm_size
  node_count            = var.node_count
  vnet_subnet_id        = var.aks_subnet_id
  os_disk_size_gb       = 128
  os_disk_type          = "Ephemeral"
  zones                 = ["1", "2", "3"]
  enable_auto_scaling   = true
  min_count             = var.node_count
  max_count             = var.node_count * 5
  max_pods              = 110
  mode                  = "User"

  node_labels = {
    "nodepool-type" = "user"
    "environment"   = var.environment
  }

  node_taints = ["workload=user:NoSchedule"]

  upgrade_settings {
    max_surge = "33%"
  }

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────
# Log Analytics Workspace for AKS monitoring
# ─────────────────────────────────────────────────────────────
resource "azurerm_log_analytics_workspace" "aks" {
  name                = "law-aks-${local.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}
