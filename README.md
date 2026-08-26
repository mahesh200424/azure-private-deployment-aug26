# Azure Private Deployment Environment

A fully private and secure application deployment environment on Azure using AKS, ACR, Key Vault, Terraform, Helm, ArgoCD, and Azure DevOps.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Azure VNet                               │
│                                                                 │
│  ┌──────────────────┐      ┌──────────────────────────────┐    │
│  │   AKS Subnet     │      │   Private Endpoints Subnet   │    │
│  │                  │      │                              │    │
│  │  ┌────────────┐  │      │  ┌────────┐  ┌───────────┐  │    │
│  │  │ System Pool│  │◄────►│  │  ACR   │  │ Key Vault │  │    │
│  │  ├────────────┤  │      │  │  PE    │  │    PE     │  │    │
│  │  │  App Pool  │  │      │  └────────┘  └───────────┘  │    │
│  │  └────────────┘  │      └──────────────────────────────┘    │
│  └──────────────────┘                                           │
│           │                                                     │
│    NAT Gateway (egress only)                                    │
└─────────────────────────────────────────────────────────────────┘
```

**Security posture:**
- AKS cluster is fully private (no public API server)
- ACR has public network access disabled, accessed via Private Endpoint
- Key Vault has public network access disabled, accessed via Private Endpoint
- Workload Identity (OIDC) used — no credentials stored in pods
- All secrets injected via CSI Secret Store Driver (never in env vars)

---

## Repository Structure

```
azure-private-deployment/
├── terraform/
│   ├── environments/
│   │   └── prod/
│   │       ├── main.tf          # Root module, calls all sub-modules
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       ├── terraform.tfvars
│   │       └── backend.tf       # Remote state (Azure Storage)
│   └── modules/
│       ├── networking/          # VNet, subnets, NSG, NAT gateway
│       ├── acr/                 # ACR + private endpoint + DNS
│       ├── keyvault/            # Key Vault + private endpoint + RBAC
│       └── aks/                 # Private AKS + workload identity + CSI
├── pipeline/
│   ├── azure-pipelines.yml      # CI/CD pipeline (Build → Push → Deploy)
│   └── Dockerfile               # Multi-stage Spring Boot image
├── helm/
│   └── myapp/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── _helpers.tpl
│           ├── deployment-blue.yaml
│           ├── deployment-green.yaml
│           ├── service.yaml         # blue, green, active services
│           ├── serviceaccount.yaml  # Workload Identity SA
│           ├── secretproviderclass.yaml
│           └── hpa.yaml
├── argocd/
│   ├── install-argocd.sh        # Bootstrap script
│   ├── project.yaml             # ArgoCD AppProject
│   ├── application.yaml         # ArgoCD Application
│   ├── blue-green-rollout.yaml  # Legacy example; not applied by bootstrap
│   └── analysis-template.yaml   # Legacy example; not applied by bootstrap
└── README.md
```

---

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Terraform | >= 1.5 | Infrastructure provisioning |
| Azure CLI | >= 2.50 | Authentication and cluster access |
| kubectl | >= 1.27 | Kubernetes management |
| Helm | >= 3.12 | Chart deployment |
| ArgoCD CLI | >= 2.8 | GitOps management |

---

## Step 1 — Bootstrap Terraform Remote State

Before running Terraform, create the remote state storage manually (this is a one-time step):

```bash
# Set variables
RG="rg-terraform-state"
SA="satfstate$(openssl rand -hex 4)"
CONTAINER="tfstate"
LOCATION="eastus"

# Create resource group
az group create --name $RG --location $LOCATION

# Create storage account
az storage account create \
  --name $SA \
  --resource-group $RG \
  --location $LOCATION \
  --sku Standard_LRS \
  --allow-blob-public-access false \
  --min-tls-version TLS1_2

# Create container
az storage container create \
  --name $CONTAINER \
  --account-name $SA

# Enable versioning (protects state history)
az storage account blob-service-properties update \
  --account-name $SA \
  --resource-group $RG \
  --enable-versioning true

echo "Storage account: $SA"
echo "Update backend.tf with: storage_account_name = \"$SA\""
```

Update `terraform/environments/prod/backend.tf` with the storage account name.

---

## Step 2 — Configure Variables

Edit `terraform/environments/prod/terraform.tfvars`:

```hcl
location            = "eastus"
resource_group_name = "rg-myapp-prod"
environment         = "prod"
aks_node_count      = 2
aks_vm_size         = "Standard_D4s_v3"
acr_name            = "acrmyappprod"      # must be globally unique
keyvault_name       = "kv-myapp-prod"    # must be globally unique
vnet_address_space  = "10.0.0.0/16"
aks_subnet_cidr     = "10.0.1.0/24"
pe_subnet_cidr      = "10.0.2.0/24"
```

---

## Step 3 — Provision Infrastructure

```bash
cd terraform/environments/prod

# Authenticate
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# Initialize
terraform init

# Review plan
terraform plan -out=tfplan

# Apply
terraform apply tfplan
```

**What gets created:**
- Resource Group
- Virtual Network + subnets (AKS, private endpoints)
- Network Security Groups
- NAT Gateway (outbound internet for AKS nodes)
- Azure Container Registry (Premium, no public access)
- Private Endpoint + Private DNS Zone for ACR
- Azure Key Vault (no public access, RBAC mode)
- Private Endpoint + Private DNS Zone for Key Vault
- Private AKS cluster (Azure CNI, Workload Identity, OIDC, CSI driver)
- Managed Identity for AKS kubelet
- Role assignments: AcrPull on ACR, Key Vault Secrets User on Key Vault

**Save outputs:**
```bash
terraform output -json > ../../../docs/terraform-outputs.json
```

---

## Step 4 — Configure AKS Access

Since the cluster is private, kubectl access requires being inside the VNet (or using Azure Bastion / jump host):

```bash
# Get credentials (run from inside VNet or via jump host)
AKS_NAME=$(terraform output -raw aks_cluster_name)
RG=$(terraform output -raw resource_group_name)

az aks get-credentials \
  --resource-group $RG \
  --name $AKS_NAME \
  --overwrite-existing

# Verify
kubectl get nodes
```

> **Note:** For local development access, use `az aks command invoke` or set up an Azure Bastion host.

---

## Step 5 — Create Workload Identity Federation

After AKS is provisioned, create the federated credential so pods can authenticate to Azure without secrets:

```bash
# Get OIDC issuer URL
OIDC_ISSUER=$(az aks show \
  --name $AKS_NAME \
  --resource-group $RG \
  --query "oidcIssuerProfile.issuerUrl" -o tsv)

# Get the managed identity client ID (from Terraform output)
CLIENT_ID=$(terraform output -raw kubelet_identity_client_id)

# Create federated credential
az identity federated-credential create \
  --name "myapp-federated-credential" \
  --identity-name "id-myapp-kubelet" \
  --resource-group $RG \
  --issuer $OIDC_ISSUER \
  --subject "system:serviceaccount:myapp:myapp" \
  --audience "api://AzureADTokenExchange"
```

Update `helm/myapp/values.yaml`:
```yaml
serviceAccount:
  annotations:
    azure.workload.identity/client-id: "<CLIENT_ID>"

keyVault:
  vaultName: "<KEY_VAULT_NAME>"
  tenantId: "<TENANT_ID>"
```

---

## Step 6 — Install ArgoCD

```bash
cd argocd

# Make executable and run
chmod +x install-argocd.sh
./install-argocd.sh
```

The script:
1. Creates `argocd` namespace
2. Installs ArgoCD via Helm (internal LoadBalancer)
3. Applies AppProject and Application manifests
4. Prints the initial admin password

---

## Step 7 — Configure Azure DevOps Pipeline

### 7.1 Create Service Connections

In Azure DevOps → Project Settings → Service Connections:

1. **ACR connection** (type: Docker Registry)
   - Registry type: Azure Container Registry
   - Name: `acr-service-connection`

2. **AKS connection** (type: Kubernetes)
   - Auth method: Azure Subscription
   - Name: `aks-service-connection`

### 7.2 Create Variable Groups

In Azure DevOps → Pipelines → Library:

**Group: `acr-secrets`**
| Variable | Value |
|----------|-------|
| ACR_NAME | your-acr-name.azurecr.io |

**Group: `git-deploy-secrets`**
| Variable | Value | Secret? |
|----------|-------|---------|
| GIT_PAT | GitHub/ADO PAT token | ✅ |
| GIT_USER_EMAIL | ci@yourorg.com | |
| GIT_USER_NAME | CI Bot | |

**Group: `pipeline-config`**
| Variable | Value |
|----------|-------|
| HELM_REPO_URL | https://github.com/yourorg/yourrepo |
| AKS_RESOURCE_GROUP | rg-myapp-prod |
| AKS_CLUSTER_NAME | aks-myapp-prod |

### 7.3 Configure Self-Hosted Agent

The pipeline uses a self-hosted agent pool (`private-vnet-pool`) inside the VNet to reach the private AKS and ACR endpoints:

```bash
# On your agent VM (inside the VNet):
mkdir myagent && cd myagent
curl -O https://vstsagentpackage.azureedge.net/agent/3.x/vsts-agent-linux-x64-3.x.tar.gz
tar zxvf *.tar.gz
./config.sh --url https://dev.azure.com/YOUR_ORG \
            --auth pat --token YOUR_PAT \
            --pool private-vnet-pool \
            --agent myagent-01
./svc.sh install && ./svc.sh start
```

### 7.4 Create Pipeline

In Azure DevOps → Pipelines → New Pipeline:
- Source: your git repo
- YAML: `pipeline/azure-pipelines.yml`

### 7.5 Configure Approval Gate

In Azure DevOps → Pipelines → Environments → `production`:
- Add approval and check
- Add required approvers

---

## Blue-Green Deployment Workflow

### How it works

```
Git push → Azure DevOps builds image → Pushes to ACR (private)
       → Updates Helm values (image tag) → ArgoCD detects change
       → Helm updates the blue and green Deployments
       → Operator switches the active service selector after verification
```

### Traffic flow

```
Ingress → myapp-active Service
              │
              ├── (activeSlot=blue)  → Blue Deployment  (v1.0)
              └── (activeSlot=green) → Green Deployment (v2.0)
```

### Verify and switch a deployment

```bash
# Check both slots and the active Service selector
kubectl get deployments,services -n myapp
kubectl get endpoints myapp-active -n myapp
```

### Switching active slot via Helm (manual override)

```bash
# Switch to green
helm upgrade myapp ./helm/myapp \
  --namespace myapp \
  --set blueGreen.activeSlot=green \
  --reuse-values

# Switch back to blue
helm upgrade myapp ./helm/myapp \
  --namespace myapp \
  --set blueGreen.activeSlot=blue \
  --reuse-values
```

---

## Security Architecture

### Connectivity (no public endpoints)

| Resource | Access Method |
|----------|--------------|
| AKS API Server | Private DNS + VNet only |
| ACR | Private Endpoint in pe_subnet |
| Key Vault | Private Endpoint in pe_subnet |
| Pod → Key Vault | Workload Identity (OIDC JWT) → Key Vault RBAC |
| Pod → ACR | Kubelet Managed Identity → AcrPull role |

### Secret injection flow

```
Pod starts
  → CSI Driver requests secret from Key Vault
    → Uses Workload Identity (federated OIDC token)
      → Azure AD validates token
        → Returns secret
          → Mounted as file at /mnt/secrets/
            → Synced to Kubernetes Secret (optional)
```

### Least-privilege role assignments

| Identity | Role | Scope |
|----------|------|-------|
| AKS Kubelet MI | AcrPull | ACR only |
| AKS Kubelet MI | Key Vault Secrets User | Key Vault only |
| AKS Kubelet MI | Network Contributor | AKS subnet only |
| ArgoCD SA | get/list/watch | myapp namespace only |

---

## Observability

ArgoCD analysis runs Prometheus queries during promotion:

| Metric | Threshold | Action on fail |
|--------|-----------|----------------|
| HTTP success rate | > 99% | Abort rollout |
| HTTP error rate (5xx) | < 1% | Abort rollout |
| p99 latency | < 500ms | Abort rollout |
| Pod restart rate | < 0.1/min | Abort rollout |

---

## Troubleshooting

### Cannot reach AKS API server
```bash
# Use az aks command invoke for one-off commands without VPN
az aks command invoke \
  --resource-group $RG \
  --name $AKS_NAME \
  --command "kubectl get nodes"
```

### ACR pull fails
```bash
# Verify private endpoint DNS resolution (from inside AKS pod)
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup youracr.azurecr.io
# Should resolve to 10.x.x.x (private IP), not public IP

# Check kubelet identity has AcrPull
az role assignment list \
  --assignee $(az aks show -g $RG -n $AKS_NAME \
    --query identityProfile.kubeletidentity.clientId -o tsv) \
  --role "AcrPull"
```

### Key Vault secret not mounting
```bash
# Check SecretProviderClass
kubectl describe secretproviderclass myapp-keyvault -n myapp

# Check pod events
kubectl describe pod <pod-name> -n myapp

# Verify workload identity is configured
kubectl get sa myapp -n myapp -o yaml | grep azure
```

### ArgoCD out of sync
```bash
# Force sync
argocd app sync myapp --force

# Check sync status
argocd app get myapp
```

---

## Cleanup

```bash
# Destroy all infrastructure (WARNING: irreversible)
cd terraform/environments/prod
terraform destroy

# This will delete:
# - AKS cluster and all workloads
# - ACR and all images
# - Key Vault and all secrets
# - VNet and all networking
# - All role assignments
```

---

## Quick Reference

```bash
# Check blue/green Deployments and active Service
kubectl get deployments,services,endpoints -n myapp

# ArgoCD sync
argocd app sync myapp

# Get ArgoCD admin password
kubectl get secret argocd-initial-admin-secret \
  -n argocd -o jsonpath="{.data.password}" | base64 -d

# Helm diff before upgrade
helm diff upgrade myapp ./helm/myapp -n myapp -f values.yaml
```
