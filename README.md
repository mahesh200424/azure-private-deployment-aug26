# Private AKS delivery platform

This repository is a working reference implementation for running a small Spring Boot service on a private Azure Kubernetes Service cluster. Infrastructure is managed with Terraform, application delivery runs through Azure DevOps, and Argo CD owns the in-cluster state.

The project uses private endpoints and federated identities instead of registry passwords or cloud credentials in pipeline variables. It is sized as a lab environment, but the identity, networking, and delivery boundaries are the same ones I would use as a starting point for a production platform.

## What is implemented

- Private AKS API with Azure CNI and Calico network policies
- Separate system and user node pools
- Premium ACR and Key Vault behind private endpoints
- Private DNS zones linked to the workload VNet
- User-assigned identities for the AKS control plane and kubelet
- Azure Workload Identity for both the application and the build agent
- Key Vault Secrets Store CSI driver with secret rotation
- Self-hosted Azure DevOps agent running as an AKS deployment
- Docker-in-Docker sidecar for image builds on the private agent
- Multi-stage Java 17 container build with tests and a smoke test
- Immutable ACR tags based on the Azure DevOps build ID
- Argo CD and Argo Rollouts blue/green deployment manifests
- Azure Blob remote state using Entra ID authentication

## Architecture

```text
Developer / GitHub
        |
        v
Azure DevOps pipeline
        |
        v
AKS-hosted agent ---------> ACR private endpoint
        |                    (federated AcrPush identity)
        |
        +---- commits image tag to GitHub
                              |
                              v
                         Argo CD
                              |
                              v
                    Argo Rollout on AKS
                              |
                              +----> Key Vault private endpoint
                                     (application workload identity)

AKS control plane, ACR, and Key Vault are not exposed through public endpoints.
Cluster and agent egress use the VNet NAT gateway.
```

The VNet is split into three subnets:

| Subnet | CIDR | Purpose |
|---|---:|---|
| AKS | `10.1.0.0/16` | Nodes and Azure CNI pod addresses |
| Private endpoints | `10.2.0.0/24` | ACR and Key Vault interfaces |
| Agent | `10.3.0.0/24` | Retained for the optional VM-agent design |

## Delivery flow

The pipeline at `pipeline/azure-pipelines.yml` performs the following sequence:

1. Check out the GitHub repository on the private agent.
2. Run Maven tests in a pinned Maven container.
3. Build the application image and run a readiness smoke test.
4. Publish the image as a pipeline artifact between stages.
5. Exchange the projected AKS service-account token for an Azure token.
6. Push the build-number tag and `latest` to the private ACR.
7. Wait for approval on the Azure DevOps `production` environment.
8. Commit the immutable image tag to `helm/myapp/values.yaml`.
9. Let Argo CD reconcile the Git commit into the cluster.

The pipeline never receives an ACR password. Its service account is federated to `mi-azdo-agent-prod`, which has `AcrPush` scoped only to this registry. The application uses a different identity with `Key Vault Secrets User` scoped only to its vault.

## Repository layout

```text
argocd/                         Argo CD project, application and bootstrap script
helm/myapp/                     Application chart and Argo Rollout
pipeline/azure-pipelines.yml    Build, push and GitOps pipeline
pipeline/azdo-agent.yaml        AKS-hosted Azure DevOps agent
pipeline/Dockerfile             Application image
terraform/environments/prod/    Production composition and values
terraform/modules/              AKS, networking, ACR, Key Vault and identity modules
src/                            Spring Boot sample service
```

## Design decisions and trade-offs

### Agent placement

The original design included a dedicated agent VM. The current environment runs the agent on the AKS user pool because the subscription has a four-vCPU regional quota. `deploy_azure_devops_agent = false` keeps the VM path available without consuming quota.

Running Docker-in-Docker is a pragmatic lab choice. The sidecar is privileged, so I would use an isolated agent pool and ephemeral jobs for a shared production platform, or replace it with a rootless builder such as BuildKit or Kaniko after validating the required registry and cache behavior.

### Capacity

The checked-in production values use one `Standard_D2s_v7` node in each pool. This fits the current quota but is not highly available. A production rollout should use at least three system nodes across zones, enough user-pool capacity for surge, Pod Disruption Budgets, and tested autoscaler limits.

### GitOps promotion

The pipeline writes an immutable build ID to Git. Argo CD has automated sync and self-heal enabled, while Argo Rollouts keeps blue/green promotion manual. This separates deployment from traffic promotion and leaves an auditable Git history.

### Access to a private cluster

Normal `kubectl` access requires private DNS connectivity through VPN, ExpressRoute, Bastion, or a host in the VNet. For bootstrap and recovery, Azure Run Command can execute a bounded command through the Azure API:

```bash
az aks command invoke \
  --resource-group rg-private-aks-prod \
  --name aks-prod-private \
  --command "kubectl get nodes"
```

## Prerequisites

| Tool | Minimum version |
|---|---:|
| Terraform | 1.3 |
| Azure CLI | 2.50 |
| kubectl | 1.27 |
| Helm | 3.12 |
| Argo CD CLI | 2.8 |

The lock file controls the exact Terraform provider versions. Azure permissions are required to create role assignments, managed identities, private DNS zones, AKS, ACR, and Key Vault resources.

## Provisioning

Create the remote-state resources once. The backend uses Entra ID rather than storage keys:

```bash
az group create --name rg-tfstate --location eastus2

az storage account create \
  --name stprivtfstateprod \
  --resource-group rg-tfstate \
  --location eastus2 \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false

az storage container create \
  --name tfstate \
  --account-name stprivtfstateprod \
  --auth-mode login
```

Initialize and apply from the environment directory:

```bash
cd terraform/environments/prod

terraform init \
  -backend-config="resource_group_name=rg-tfstate" \
  -backend-config="storage_account_name=stprivtfstateprod" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=prod/azure-private-deployment.tfstate" \
  -backend-config="use_azuread_auth=true"

terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Review `terraform/environments/prod/terraform.tfvars` before applying. Resource names such as ACR, Key Vault, and the state storage account must be globally unique.

## Bootstrap the private agent

Create a PAT with the minimum Azure DevOps scope required to register an agent, store it as a Kubernetes secret, and do not put it in Git or shell history. The manifest also sets `VSO_AGENT_IGNORE=AZP_TOKEN` so the token is not advertised as an agent capability.

```bash
kubectl create namespace azdo-agents --dry-run=client -o yaml | kubectl apply -f -

read -rsp 'Azure DevOps PAT: ' AZDO_PAT
printf '%s' "$AZDO_PAT" | kubectl -n azdo-agents create secret generic azdo-agent-pat \
  --from-file=AZP_TOKEN=/dev/stdin
unset AZDO_PAT

kubectl apply -f pipeline/azdo-agent.yaml
kubectl -n azdo-agents rollout status deployment/azdo-agent
```

For a private cluster without local network access, upload the manifest with `az aks command invoke --file`. Create the secret manifest in a protected temporary file and remove it immediately after use.

The `platform-config` Azure DevOps variable group contains:

| Variable | Value |
|---|---|
| `ACR_NAME` | `acrprivaksprod001` |
| `ACR_LOGIN_SERVER` | `acrprivaksprod001.azurecr.io` |
| `APP_NAME` | `myapp` |

The pipeline uses the `private-vnet-pool` agent pool and a `production` environment approval check.

## Bootstrap GitOps

The chart values contain the current ACR, Key Vault, tenant, and workload-identity client ID. For another subscription or environment, replace them using Terraform outputs before installing Argo CD.

```bash
cd argocd
./install-argocd.sh --dry-run
./install-argocd.sh
```

The bootstrap script pins Argo CD and Argo Rollouts versions, creates the namespaces, applies the project and application, and exposes the Argo CD server through an internal load balancer.

Useful rollout commands:

```bash
kubectl argo rollouts get rollout myapp -n myapp --watch
kubectl argo rollouts promote myapp -n myapp
kubectl argo rollouts abort myapp -n myapp
kubectl argo rollouts undo myapp -n myapp
```

## Operations

### Pipeline agent

```bash
kubectl -n azdo-agents get pods -l app=azdo-agent
kubectl -n azdo-agents logs deployment/azdo-agent -c agent --tail=100
kubectl -n azdo-agents rollout restart deployment/azdo-agent
```

### ACR and workload identity

```bash
az acr repository show-tags \
  --name acrprivaksprod001 \
  --repository myapp \
  --orderby time_desc \
  --top 10

kubectl -n myapp get serviceaccount myapp -o yaml
kubectl -n myapp describe secretproviderclass
```

### Argo CD and rollout state

```bash
argocd app get myapp
argocd app diff myapp
kubectl -n myapp get rollouts,replicasets,services,pods
```

### Common failure modes

| Symptom | First check |
|---|---|
| Agent offline | Agent pod logs and PAT validity |
| `az login` fails in pipeline | Service-account annotation, pod workload-identity label, projected token file |
| ACR push denied | `AcrPush` assignment on the agent identity and private DNS resolution |
| Image pull denied | Kubelet `AcrPull` assignment |
| Secret volume fails | Federated subject, Key Vault role, `SecretProviderClass`, private endpoint DNS |
| Rollout remains paused | Expected when manual blue/green promotion is enabled |

## Security notes

- PATs are bootstrap credentials for agent registration only. Rotate them and keep them out of repository history, logs, and agent capabilities.
- ACR public access and Key Vault public access are disabled.
- The application and pipeline do not share a managed identity.
- Kubernetes secrets are not used for application secrets; the CSI driver mounts Key Vault values as read-only files.
- Terraform state can contain sensitive metadata and must remain in the protected remote backend.
- The privileged Docker sidecar is the largest remaining security trade-off and should not host untrusted pull-request builds.

## Validation

```bash
docker run --rm \
  -v "$PWD:/workspace" \
  -w /workspace \
  maven:3.9-eclipse-temurin-17 \
  mvn --no-transfer-progress test
terraform fmt -check -recursive
terraform -chdir=terraform/environments/prod validate
helm lint helm/myapp
```

Pipeline run 17 validated the complete path: test, image build, smoke test, workload-identity login, private ACR push, production approval, and GitOps revision commit.

## Cleanup

Review the plan before destroying the environment because ACR images and the AKS cluster are not recoverable from Terraform state alone:

```bash
cd terraform/environments/prod
terraform plan -destroy
terraform destroy
```

Key Vault soft-delete remains enabled. The remote-state storage account is bootstrapped separately and is intentionally not part of this destroy operation.
