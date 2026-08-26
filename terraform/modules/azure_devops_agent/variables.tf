variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "environment" { type = string }
variable "subnet_id" { type = string }
variable "admin_username" { type = string }
variable "admin_ssh_public_key" {
  description = "SSH public key for break-glass VM administration. The VM has no public IP."
  type        = string
}
variable "vm_size" {
  description = "Small VM size suitable for a temporary test agent."
  type        = string
  default     = "Standard_B2s"
}
