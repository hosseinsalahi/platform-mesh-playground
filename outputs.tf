output "public_ip" {
  description = "Public IP address of the VM"
  value       = scaleway_instance_ip.public.address
}

output "private_ip" {
  description = "Private IP address of the VM"
  value       = local.private_ip
}

output "instance_id" {
  description = "Instance ID of the VM"
  value       = scaleway_instance_server.vm.id
}

output "ssh_command" {
  description = "SSH command for the VM"
  value       = "ssh ${var.vm_user}@${scaleway_instance_ip.public.address}"
}

output "portal_tunnel_command" {
  description = "SSH local-forwarding command for the Platform Mesh portal"
  value       = "ssh -L 8443:127.0.0.1:8443 ${var.vm_user}@${scaleway_instance_ip.public.address}"
}

output "portal_url" {
  description = "Portal URL to open after the SSH tunnel is established"
  value       = "https://portal.localhost:8443"
}

output "warp_portal_url" {
  description = "Portal URL to open when connected via Cloudflare WARP (requires Private Network routing)"
  value       = "https://portal.${local.private_ip}:8443"
}

output "warp_k8s_api_server" {
  description = "Kubernetes API Server address when connected via Cloudflare WARP"
  value       = "https://${local.private_ip}:6443"
}

output "warp_kubeconfig_command" {
  description = "Command to download and prepare a WARP-compatible direct K8s kubeconfig"
  value       = "scp ${var.vm_user}@${scaleway_instance_ip.public.address}:/home/${var.vm_user}/.kube/config ./kind.kubeconfig && sed -i '' 's/127.0.0.1:6443/${local.private_ip}:6443/g' ./kind.kubeconfig && export KUBECONFIG=$(pwd)/kind.kubeconfig"
}

output "mkcert_root_ca_copy_command" {
  description = "Command to copy the VM-generated mkcert root CA to your workstation if you want to trust the browser certificate locally"
  value       = "scp ${var.vm_user}@${scaleway_instance_ip.public.address}:/home/${var.vm_user}/.local/share/mkcert/rootCA.pem ./platform-mesh-rootCA.pem"
}
