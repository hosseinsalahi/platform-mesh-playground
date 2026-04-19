terraform {
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.0"
    }
  }
  required_version = ">= 1.0"
}

provider "scaleway" {}

locals {
  private_ip = one([for ip in scaleway_instance_server.vm.private_ips : ip.address if can(regex("^[0-9.]+$", ip.address))])
}

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
  description = "CIDR block allowed to reach SSH on the VM. STRONGLY RECOMMENDED to restrict this to your specific IP address (e.g., 'x.x.x.x/32') to prevent unauthorized access."
  type        = string
  default     = "0.0.0.0/0"
}

variable "platform_mesh_version" {
  description = "Git ref from platform-mesh/helm-charts to deploy during first boot"
  type        = string
  default     = "0.2.0"
}

variable "cloudflare_tunnel_token" {
  description = "Cloudflare Tunnel Token to securely expose the K8s API and Portal"
  type        = string
  sensitive   = true
}

resource "scaleway_vpc_private_network" "pn" {
  name = "platform-mesh-priv-net"
  tags = ["platform-mesh", "private"]
}

resource "scaleway_instance_ip" "public" {}

resource "scaleway_instance_security_group" "ssh_only" {
  name                    = "platform-mesh-vm"
  description             = "Allow SSH for administration; Platform Mesh stays on localhost and is accessed through an SSH tunnel"
  inbound_default_policy  = "drop"
  outbound_default_policy = "accept"

  inbound_rule {
    action   = "accept"
    port     = 22
    protocol = "TCP"
    ip_range = var.ssh_allowed_cidr
  }

  inbound_rule {
    action   = "accept"
    port     = 8443
    protocol = "TCP"
    ip_range = "0.0.0.0/0"
  }

  inbound_rule {
    action   = "accept"
    port     = 6443
    protocol = "TCP"
    ip_range = "0.0.0.0/0"
  }

  inbound_rule {
    action   = "accept"
    protocol = "ICMP"
    ip_range = "0.0.0.0/0"
  }
}

resource "scaleway_instance_server" "vm" {
  type              = "POP2-HC-16C-32G"
  image             = "debian_bookworm"
  ip_id             = scaleway_instance_ip.public.id
  security_group_id = scaleway_instance_security_group.ssh_only.id

  private_network {
    pn_id = scaleway_vpc_private_network.pn.id
  }

  root_volume {
    volume_type = "sbs_volume"
    size_in_gb  = 100
  }

  cloud_init = templatefile("${path.module}/cloud-init.yml", {
    bootstrap_script = templatefile("${path.module}/bootstrap-platform-mesh.sh.tftpl", {
      platform_mesh_version   = var.platform_mesh_version
      vm_user                 = var.vm_user
      cloudflare_tunnel_token = var.cloudflare_tunnel_token
      public_ip               = scaleway_instance_ip.public.address
    })
    ssh_public_key = var.ssh_public_key
    vm_user        = var.vm_user
  })

  tags = ["platform-mesh", "simple-vm"]
}
