resource "scaleway_vpc_private_network" "pn" {
  name = "platform-mesh-priv-net"
  tags = ["platform-mesh", "private"]
}

resource "scaleway_instance_ip" "public" {}

resource "scaleway_instance_security_group" "ssh_only" {
  name                    = "platform-mesh-vm"
  description             = "Allow SSH for administration; app traffic should arrive through Cloudflare WARP instead of public ingress"
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
    protocol = "ICMP"
    ip_range = "0.0.0.0/0"
  }
}

resource "scaleway_instance_server" "vm" {
  type              = var.scaleway_instance_type
  image             = var.scaleway_instance_image
  ip_id             = scaleway_instance_ip.public.id
  security_group_id = scaleway_instance_security_group.ssh_only.id

  # cloud-init is consumed on first boot; treating it as immutable avoids perpetual drift on an existing VM.
  lifecycle {
    ignore_changes = [cloud_init]
  }

  private_network {
    pn_id = scaleway_vpc_private_network.pn.id
  }

  root_volume {
    volume_type = "sbs_volume"
    size_in_gb  = var.scaleway_root_volume_size_gb
  }

  cloud_init = templatefile("${path.module}/cloud-init.yml", {
    bootstrap_script = templatefile("${path.module}/bootstrap.sh.tftpl", {
      platform_mesh_version = var.platform_mesh_version
      vm_user               = var.vm_user
    })
    ssh_public_key = var.ssh_public_key
    vm_user        = var.vm_user
  })

  tags = var.scaleway_instance_tags
}
