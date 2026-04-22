#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

output_raw() {
  terraform -chdir="$repo_root" output -raw "$1"
}

require_output() {
  local name="$1"

  if ! terraform -chdir="$repo_root" output "$name" >/dev/null 2>&1; then
    echo "Missing Terraform output: $name" >&2
    echo "Run terraform apply successfully before executing this script." >&2
    exit 1
  fi
}

require_output "warp_private_route_cidr"
require_output "warp_portal_url"
require_output "admin_warp_kubeconfig_command"
require_output "private_ip"
require_output "public_ip"

warp_private_route_cidr="$(output_raw "warp_private_route_cidr")"
warp_portal_url="$(output_raw "warp_portal_url")"
admin_warp_kubeconfig_command="$(output_raw "admin_warp_kubeconfig_command")"
private_ip="$(output_raw "private_ip")"
public_ip="$(output_raw "public_ip")"
vm_user="$(printf '%s\n' "$admin_warp_kubeconfig_command" | sed -nE 's#^scp ([^@[:space:]]+)@[^:]+:.*#\1#p')"

if [[ -z "$vm_user" ]]; then
  vm_user="$(printf '%s\n' "$admin_warp_kubeconfig_command" | sed -nE 's#.*:/home/([^/]+)/\.kube/config.*#\1#p')"
fi

if [[ -z "$vm_user" ]]; then
  echo "Unable to derive the VM user from admin_warp_kubeconfig_command" >&2
  exit 1
fi

ssh_target="${vm_user}@${public_ip}"
warp_portal_domain="$(output_raw "warp_portal_url" | sed -nE 's#^https://([^:]+):.*#\1#p')"
warp_portal_hosts_entry="${private_ip} ${warp_portal_domain}"
team_kubeconfig_copy_command="scp ${ssh_target}:/home/${vm_user}/.kube/platform-mesh-team.kubeconfig ./platform-mesh-team.kubeconfig"
mkcert_root_ca_copy_command="scp ${ssh_target}:/home/${vm_user}/.local/share/mkcert/rootCA.pem ./platform-mesh-rootCA.pem"
portal_port_forward_command="kubectl --kubeconfig ./platform-mesh-team.kubeconfig -n default port-forward svc/traefik 8443:8443"

if [[ "${warp_portal_domain}" == *.localhost ]]; then
  cat <<EOF
Team onboarding

1. Install Cloudflare One and enroll in your existing Zero Trust WARP flow.
2. Connect WARP and verify that this route is active:
   ${warp_private_route_cidr}

3. An admin should retrieve and securely distribute the restricted team kubeconfig:
   ${team_kubeconfig_copy_command}

4. Trust the portal certificate locally if your browser warns:
   ${mkcert_root_ca_copy_command}

5. Start a local port-forward to Traefik:
   ${portal_port_forward_command}

6. Open the portal:
   ${warp_portal_url}
EOF
  exit 0
fi

cat <<EOF
Team onboarding

1. Install Cloudflare One and enroll in your existing Zero Trust WARP flow.
2. Connect WARP and verify that this route is active:
   ${warp_private_route_cidr}

3. Add this hosts entry on your workstation:
   ${warp_portal_hosts_entry}

4. An admin should retrieve and securely distribute the restricted team kubeconfig:
   ${team_kubeconfig_copy_command}

5. Trust the portal certificate locally if your browser warns:
   ${mkcert_root_ca_copy_command}

6. Open the portal:
   ${warp_portal_url}
EOF
