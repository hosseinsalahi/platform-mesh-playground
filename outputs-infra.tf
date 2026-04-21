output "public_ip" {
  description = "Public IP address of the VM"
  value       = scaleway_instance_ip.public.address
}

output "private_ip" {
  description = "Private IP address of the VM"
  value       = local.private_ip
}

output "warp_portal_url" {
  description = "Portal URL to open. When platform_mesh_base_domain is portal.localhost, access it through a local kubectl port-forward to the traefik service."
  value       = "https://${var.platform_mesh_base_domain}:8443"
}

output "warp_private_route_cidr" {
  description = "CIDR that should be routed through Cloudflare WARP for direct access to this VM"
  value       = local.warp_route_cidr
}

output "admin_warp_kubeconfig_command" {
  description = "Admin-only command to download and prepare the VM user's full-access WARP-compatible kubeconfig"
  value       = "scp ${var.vm_user}@${scaleway_instance_ip.public.address}:/home/${var.vm_user}/.kube/config ./kind.kubeconfig && perl -0pi -e 's/127\\.0\\.0\\.1:6443/${local.private_ip}:6443/g' ./kind.kubeconfig && export KUBECONFIG=$(pwd)/kind.kubeconfig"
}
