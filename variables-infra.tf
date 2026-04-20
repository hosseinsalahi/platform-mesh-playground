variable "vm_user" {
  description = "Linux user created on the VM for SSH and day-to-day operations"
  type        = string
  default     = "naira"
}

variable "ssh_public_key" {
  description = "SSH public key authorized for the VM user"
  type        = string
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed to reach SSH on the VM. Pass a specific admin source range such as '203.0.113.10/32'."
  type        = string

  validation {
    condition     = can(cidrhost(var.ssh_allowed_cidr, 0))
    error_message = "ssh_allowed_cidr must be a valid IPv4 or IPv6 CIDR block, for example '203.0.113.10/32'."
  }
}

variable "platform_mesh_version" {
  description = "Git ref from platform-mesh/helm-charts to deploy during first boot"
  type        = string
  default     = "0.2.0"
}

variable "scaleway_instance_type" {
  description = "Scaleway instance type for the VM."
  type        = string
  default     = "POP2-HC-16C-32G"
}

variable "scaleway_instance_image" {
  description = "Scaleway image used for the VM."
  type        = string
  default     = "debian_bookworm"
}

variable "scaleway_root_volume_size_gb" {
  description = "Root disk size for the VM in GiB."
  type        = number
  default     = 100

  validation {
    condition     = var.scaleway_root_volume_size_gb >= 20
    error_message = "scaleway_root_volume_size_gb must be at least 20 GiB."
  }
}

variable "scaleway_instance_tags" {
  description = "Tags applied to the VM."
  type        = list(string)
  default     = ["platform-mesh", "simple-vm"]
}
