# ─────────────────────────────────────────────────────────────
# Remote state — Azure Blob Storage backend
#
# Pre-requisites (run once before `terraform init`):
#   az group create -n rg-tfstate -l eastus2
#   az storage account create -n stprivtfstateprod -g rg-tfstate \
#     --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 \
#     --allow-blob-public-access false
#   az storage container create -n tfstate \
#     --account-name stprivtfstateprod --auth-mode login
#
# Initialize with:
#   terraform init \
#     -backend-config="resource_group_name=rg-tfstate" \
#     -backend-config="storage_account_name=stprivtfstateprod" \
#     -backend-config="container_name=tfstate" \
#     -backend-config="key=prod/azure-private-deployment.tfstate" \
#     -backend-config="use_azuread_auth=true"
# ─────────────────────────────────────────────────────────────
terraform {
  backend "azurerm" {
    # Values intentionally left empty; supply at init time via
    # -backend-config flags or a backend.hcl partial config file.
    # This prevents secrets from being committed to source control.
    resource_group_name  = ""
    storage_account_name = ""
    container_name       = ""
    key                  = ""
    use_azuread_auth     = true
  }
}
