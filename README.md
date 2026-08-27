# Azure Private Deployment Environment

A fully private and secure application deployment environment on Azure using AKS, ACR, Key Vault, Terraform, Helm, ArgoCD, and Azure DevOps.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                            Azure VNet (10.0.0.0/8)                   │
│                                                                      │
│  ┌─────────────────┐   ┌──────────────────────────┐   ┌──────────┐  │
│  │  AKS Subnet     │   │  Private Endpoints Subnet │   │  Agent   │  │
│  │  10.1.0.0/16    │   │  10.2.0.0/24              │   │  Subnet  │  │
│  │                 │   │                           │   │10.3.0.0/ │  │
│  │ ┌─────────────┐ │   │  ┌────────┐  ┌─────────┐ │   │   24     │  │
│  │ │ System Pool │ │◄──►│  │  ACR   │  │Key Vault│ │   │ ┌──────┐ │  │
│  │ ├─────────────┤ │   │  │  PE    │  │   PE    │ │   │ │ ADO  │ │  │
│  │ │  User Pool  │ │   │  └────────┘  └─────────┘ │   │ │Agent │ │  │
│  │ └─────────────┘ │   └──────────────────────────┘   │ └──────┘ │  │
│  └─────────────────┘                                   └──────────┘  │
│           │                                                          │
│    NAT Gateway (egress only)                                         │
└──────────────────────────────────────────────────────────────────────┘
```

**Security posture:**
- AKS cluster is fully private (no public API server endpoint)
- ACR has public network access disabled, accessed via Private Endpoint
- Key Vault has public network access disabled, accessed via Private Endpoint
- Workload Identity (OIDC) used — no credentials stored in pods
- All secrets injected via CSI Secret Store Driver, mounted as files at `/mnt/secrets/`
- Azure DevOps agent runs inside the VNet (agent subnet) — provisioned by Terraform

---

## Repository Structure

```
azure-private-deployment/
├── terraform/
│   ├── environments/
│   │   └── prod/
│   │       ├── main.tf          # Root module — wires all sub-modules together
│   │       ├── variables.tf     # Input variables with validation rules
│   │       ├── outputs.tf       # Outputs needed for Step 5 (GitOps values)
│   │       ├── terraform.tfvars # Sample values — replace before applying
│   │       └── backend.tf       # Remote state (Azure Blob, AAD auth, no SAS keys)
│   └── modules/
│       ├── networking/          # VNet, subnets (AKS/PE/agent), NSG, NAT gateway
│       ├── acr/                 # ACR Premium + private endpoint + DNS zone
│       ├── keyvault/            # Key Vault + private endpoint + RBAC assignments
│       ├── aks/                 # Private AKS, system+user pools, workload identity, CSI, Log Analytics
│       ├── workload_identity/   # Dedicated MI + federated OIDC credential for app pods
│       └── azure_devops_agent/  # Self-hosted agent VM (Ubuntu 22.04, system MI, cloud-init)
├── pipeline/
│   ├── azure-pipelines.yml      # CI/CD: Build → Test → Push → GitOps commit
│   └── Dockerfile               # Multi-stage Spring Boot image (Maven builder + JRE runtime)
├── helm/
│   └── myapp/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── _helpers.tpl
│           ├── rollout.yaml             # Argo Rollouts blue/green Rollout resource
│           ├── service.yaml             # Active + preview Services (controller-owned)
│           ├── serviceaccount.yaml      # Workload Identity SA
│           ├── secretproviderclass.yaml # CSI SecretProviderClass → Key Vault
│           └── networkpolicy.yaml
├── argocd/
│   ├── install-argocd.sh        # Bootstrap script (idempotent, supports --dry-run)
│   ├── project.yaml             # AppProject with RBAC roles and sync windows
│   └── application.yaml         # ArgoCD Application (automated sync, self-heal)
├── src/                         # Spring Boot application source
├── pom.xml
└── README.md
```

---

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Terraform | >= 1.3 | Infrastructure provisioning (actual `required_version` in main.tf) |
| Azure CLI | >= 2.50 | Authentication and cluster access |
| kubectl | >= 1.27 | Kubernetes management |
| Helm | >= 3.12 | Chart deployment |
| ArgoCD CLI | >= 2.8 | GitOps management |
| jq | any | Used by `install-argocd.sh` pre-flight check |

> **Note:** The Terraform lock file pins `azurerm ~> 3.117` and `azuread ~> 2.53`. Run `terraform init` to restore the exact provider versions.

---

## Step 1 — Bootstrap Terraform Remote State

Create the remote state storage once before running `terraform init`. The backend is configured to use AAD auth (`use_azuread_auth = true`) — no SAS keys or storage account keys are needed.

```bash
RG="rg-tfstate"
SA="stprivtfstateprod"   # must be globally unique
CONTAINER="tfstate"
LOCATION="eastus2"       # match var.location in terraform.tfvars

az group create --name $RG --location $LOCATION

az storage account create \
  --name $SA \
  --resource-group $RG \
  --location $LOCATION \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false

az storage container create \
  --name $CONTAINER \
  --account-name $SA \
  --auth-mode login

# Protect state history
az storage account blob-service-properties update \
  --account-name $SA \
  --resource-group $RG \
  --enable-versioning true

# Grant yourself Storage Blob Data Contributor so AAD auth works
az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee $(az ad signed-in-user show --query id -o tsv) \
  --scope $(az storage account show -n $SA -g $RG --query id -o tsv)
```

Then initialise with backend config flags (values are intentionally not committed to `backend.tf`):

```bash
cd terraform/environments/prod

terraform init \
  -backend-config="resource_group_name=$RG" \
  -backend-config="storage_account_name=$SA" \
  -backend-config="container_name=$CONTAINER" \
  -backend-config="key=prod/azure-private-deployment.tfstate" \
  -backend-config="use_azuread_auth=true"
```

---

## Step 2 — Configure Variables

Edit `terraform/environments/prod/terraform.tfvars`. The file ships with working sample values — replace anything marked below:

```hcl
location            = "eastus2"
resource_group_name = "rg-private-aks-prod"
environment         = "prod"

# AKS
aks_node_count = 3          # per pool; auto-scaler max = node_count × 3 (system) / × 5 (user)
aks_vm_size    = "Standard_D4ds_v5"

# ACR — globally unique, alphanumeric only, 5-50 chars
acr_name = "acrprivaksprod001"

# Key Vault — globally unique, 3-24 chars
keyvault_name = "kv-priv-aks-prod-001"

# Networking — subnets must not overlap
vnet_address_space = "10.0.0.0/8"
aks_subnet_cidr    = "10.1.0.0/16"
pe_subnet_cidr     = "10.2.0.0/24"
agent_subnet_cidr  = "10.3.0.0/24"

# Agent VM SSH key — paste the contents of your public key file
agent_admin_username       = "azureuser"
agent_admin_ssh_public_key = "ssh-rsa AAAA..."   # replace with your actual key
agent_vm_size              = "Standard_D2s_v3"
```

> **Important:** `terraform.tfvars` is tracked in git. Never put private keys or secrets here. The SSH key is a public key — that's fine. The actual agent registration (PAT) happens via cloud-init on first boot.

---

## Step 3 — Provision Infrastructure

```bash
cd terraform/environments/prod

az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"

terraform plan -out=tfplan
terraform apply tfplan
```

**What gets created:**
- Resource Group
- Virtual Network with three subnets: AKS (`10.1.0.0/16`), Private Endpoints (`10.2.0.0/24`), Agent (`10.3.0.0/24`)
- Network Security Groups + NAT Gateway (outbound for AKS nodes)
- Azure Container Registry (Premium, public access disabled)
- Private Endpoint + Private DNS Zone for ACR
- Azure Key Vault (public access disabled, RBAC mode, soft-delete protected)
- Private Endpoint + Private DNS Zone for Key Vault
- Private AKS cluster — Azure CNI, Calico network policy, system + user node pools, auto-scaling, availability zones, Workload Identity, OIDC issuer, CSI driver, Log Analytics
- User-assigned managed identities: AKS control plane, AKS kubelet, workload identity (app pods)
- Federated OIDC credential on the workload identity (wired to the `myapp` SA in the `myapp` namespace)
- Azure DevOps agent VM (Ubuntu 22.04, system-assigned MI, cloud-init bootstrap)
- Role assignments: AcrPull (kubelet → ACR), AcrPush (agent MI → ACR), Key Vault Secrets User (workload identity → Key Vault)

**Save outputs for the next step:**
```bash
terraform output -json > ../../../docs/terraform-outputs.json
```

---

## Step 4 — Configure AKS Access

The API server has no public endpoint. Access requires being inside the VNet or using `az aks command invoke`:

```bash
AKS_NAME=$(terraform output -raw aks_cluster_name)
RG=$(terraform output -raw resource_group_name)

# Option A: from inside the VNet (agent VM or Bastion)
az aks get-credentials --resource-group $RG --name $AKS_NAME --overwrite-existing
kubectl get nodes

# Option B: one-off commands without VPN (uses Azure API, slower)
az aks command invoke --resource-group $RG --name $AKS_NAME --command "kubectl get nodes"
```

---

## Step 5 — Configure GitOps Values

Terraform creates the workload identity and its federated credential automatically. Before ArgoCD applies the chart, update `helm/myapp/values.yaml` with Terraform outputs:

```yaml
serviceAccount:
  annotations:
    azure.workload.identity/client-id: "<terraform output -raw workload_identity_client_id>"

image:
  repository: "<terraform output -raw acr_login_server>/myapp"

keyVault:
  vaultName: "<terraform output -raw keyvault_name>"   # just the name, not the URI
  tenantId: "<az account show --query tenantId -o tsv>"
```

The `application.yaml` already points to the real repository URL. If you fork this repo, update `argocd/application.yaml` and `argocd/project.yaml` with your clone URL and configure ArgoCD with read-only repository credentials.

> **Do not** add a federated credential to the kubelet identity — it is scoped to AcrPull only and is not a workload identity.

---

## Step 6 — Install ArgoCD

```bash
cd argocd
chmod +x install-argocd.sh

# Dry-run first to see what will happen
./install-argocd.sh --dry-run

# Install (will prompt for confirmation)
./install-argocd.sh
```

The script is idempotent — safe to re-run for upgrades. It:
1. Creates `argocd`, `argo-rollouts`, and `myapp` namespaces
2. Installs ArgoCD `v2.11.3` and Argo Rollouts `v1.7.1` via Helm (pinned versions)
3. Patches `argocd-server` to an internal Azure Load Balancer (private IP only)
4. Applies `project.yaml` then `application.yaml`
5. Prints the one-time bootstrap password

**After first login:**
```bash
argocd account update-password
kubectl delete secret argocd-initial-admin-secret -n argocd
```

Configure SSO (Azure AD OIDC) and update the `groups` fields in `argocd/project.yaml` with your actual Azure AD group names before granting team access.

---

## Step 7 — Configure Azure DevOps Pipeline

### 7.1 Register the Agent VM

The agent VM is provisioned by Terraform but must be registered in Azure DevOps manually (or via cloud-init — see `terraform/modules/azure_devops_agent/cloud-init.yaml.tftpl`):

```bash
# SSH into the agent VM (get its private IP from Terraform output)
AGENT_VM=$(terraform output -raw agent_vm_name)
AGENT_IP=$(az vm show -g $RG -n $AGENT_VM -d --query privateIps -o tsv)

# From inside the VNet / Bastion:
ssh azureuser@$AGENT_IP

# On the agent VM:
mkdir myagent && cd myagent
curl -O https://vstsagentpackage.azureedge.net/agent/3.x/vsts-agent-linux-x64-3.x.tar.gz
tar zxvf *.tar.gz
./config.sh --url https://dev.azure.com/YOUR_ORG \
            --auth pat --token YOUR_PAT \
            --pool private-vnet-pool \
            --agent myagent-01
./svc.sh install && ./svc.sh start
```

### 7.2 Create Variable Groups

In Azure DevOps → Pipelines → Library, create group `platform-config`:

| Variable | Value |
|----------|-------|
| `ACR_NAME` | `terraform output -raw acr_name` (e.g. `acrprivaksprod001`) |
| `ACR_LOGIN_SERVER` | `terraform output -raw acr_login_server` |
| `APP_NAME` | `myapp` |

The agent VM's system-assigned MI has `AcrPush` — no Docker credentials or registry service connection needed. Enable **Allow scripts to access the OAuth token** and grant the build service identity **Contribute** on the repo so the pipeline can commit the image tag back to `helm/myapp/values.yaml`.

### 7.3 Create Pipeline

Azure DevOps → Pipelines → New Pipeline → select your repo → YAML: `pipeline/azure-pipelines.yml`

### 7.4 Configure Approval Gate

Azure DevOps → Pipelines → Environments → `production` → Add approval check with required approvers.

---

## Blue-Green Deployment Workflow

### How it works

```
git push → Azure DevOps builds + tests image (Maven in Docker, smoke test)
        → Pushes immutable tag to private ACR
        → Commits image.tag to helm/myapp/values.yaml → ArgoCD detects change
        → Argo Rollouts creates new ReplicaSet behind preview Service
        → Pre-promotion analysis runs (Prometheus metrics)
        → Operator promotes or aborts
```

### Traffic flow

```
Ingress → myapp-active Service  → stable ReplicaSet   (live traffic)
       → myapp-preview Service → new ReplicaSet      (validation traffic)
```

### Verify and promote

```bash
# Watch the rollout progress
kubectl argo rollouts get rollout myapp -n myapp --watch

# Check preview endpoints are healthy before promoting
kubectl get endpoints myapp-preview -n myapp

# Promote (switches active Service selector to new ReplicaSet)
kubectl argo rollouts promote myapp -n myapp

# Abort (leaves active revision serving, scales down preview)
kubectl argo rollouts abort myapp -n myapp

# Roll back to the previous completed revision
kubectl argo rollouts undo myapp -n myapp
```

---

## Security Architecture

### Connectivity (no public endpoints)

| Resource | Access Method |
|----------|--------------|
| AKS API Server | Private DNS + VNet only |
| ACR | Private Endpoint in `pe_subnet` (`10.2.0.0/24`) |
| Key Vault | Private Endpoint in `pe_subnet` (`10.2.0.0/24`) |
| Pod → Key Vault | Workload Identity (OIDC JWT) → Key Vault RBAC |
| Pod → ACR | Kubelet Managed Identity → AcrPull role |
| Azure DevOps → ACR | Agent VM system MI → AcrPush role |

### Secret injection flow

```
Pod starts
  → CSI Driver requests secret from Key Vault
    → Uses Workload Identity (federated OIDC token from OIDC issuer)
      → Azure AD validates token against federated credential
        → Returns secret value
          → Mounted as read-only file at /mnt/secrets/
```

Secrets are never in environment variables, never in Kubernetes Secrets by default (the `syncSecret` option in SecretProviderClass is disabled).

### Least-privilege role assignments

| Identity | Role | Scope |
|----------|------|-------|
| AKS Control Plane MI | Private DNS Zone Contributor | AKS private DNS zone |
| AKS Control Plane MI | Network Contributor | AKS subnet |
| AKS Kubelet MI | AcrPull | ACR only |
| myapp Workload Identity | Key Vault Secrets User | Key Vault only |
| Azure DevOps Agent MI | AcrPush | ACR only |
| ArgoCD SA | get/list/watch | `myapp` namespace only |

---

## Observability

AKS ships logs to Log Analytics (workspace provisioned by the `aks` module). ArgoCD analysis runs Prometheus queries during blue-green promotion:

| Metric | Threshold | Action on fail |
|--------|-----------|----------------|
| HTTP success rate | > 99% | Abort rollout |
| HTTP error rate (5xx) | < 1% | Abort rollout |
| p99 latency | < 500ms | Abort rollout |
| Pod restart rate | < 0.1/min | Abort rollout |

> Prometheus must be deployed in the cluster for analysis to work. The `project.yaml` whitelists `monitoring.coreos.com` resources — deploy the kube-prometheus-stack chart into the `monitoring` namespace.

---

## Troubleshooting

### Cannot reach AKS API server
```bash
# One-off commands without VPN
az aks command invoke \
  --resource-group $RG \
  --name $AKS_NAME \
  --command "kubectl get nodes"
```

### ACR pull fails
```bash
# Verify private DNS resolves to a private IP (from inside a pod)
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup acrprivaksprod001.azurecr.io
# Expected: resolves to 10.2.x.x — if you see a public IP, the PE DNS zone is not linked

# Verify kubelet identity has AcrPull
az role assignment list \
  --assignee $(az aks show -g $RG -n $AKS_NAME \
    --query identityProfile.kubeletidentity.clientId -o tsv) \
  --role "AcrPull"
```

### Key Vault secret not mounting
```bash
kubectl describe secretproviderclass myapp-akv -n myapp
kubectl describe pod <pod-name> -n myapp

# Verify workload identity annotation is set on the SA
kubectl get sa myapp -n myapp -o yaml | grep azure
```

### ArgoCD out of sync
```bash
argocd app sync myapp --force
argocd app get myapp
```

### Agent VM not appearing in Azure DevOps pool
```bash
# Check cloud-init completed successfully
az vm run-command invoke -g $RG -n $AGENT_VM \
  --command-id RunShellScript \
  --scripts "cat /var/log/cloud-init-output.log | tail -50"
```

---

## Cleanup

```bash
# Destroy all infrastructure — this is irreversible
cd terraform/environments/prod
terraform destroy

# Deletes: AKS cluster, ACR + all images, Key Vault + all secrets,
#          VNet, agent VM, Log Analytics workspace, all role assignments
```

---

## Quick Reference

```bash
# Blue-green status
kubectl argo rollouts get rollout myapp -n myapp --watch

# ArgoCD sync
argocd app sync myapp

# Get ArgoCD admin password (if secret still exists)
kubectl get secret argocd-initial-admin-secret \
  -n argocd -o jsonpath="{.data.password}" | base64 -d

# Port-forward ArgoCD UI locally (from inside VNet or via Bastion)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Helm diff before a manual upgrade
helm diff upgrade myapp ./helm/myapp -n myapp -f helm/myapp/values.yaml

# Check all deployments, services, endpoints in myapp namespace
kubectl get rollouts,services,endpoints -n myapp
```
