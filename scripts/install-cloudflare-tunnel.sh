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

if [[ -z "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]]; then
  echo "Set CLOUDFLARE_TUNNEL_TOKEN before running this script." >&2
  exit 1
fi

require_output "admin_warp_kubeconfig_command"
require_output "public_ip"

admin_warp_kubeconfig_command="$(output_raw "admin_warp_kubeconfig_command")"
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
remote_token_path="/tmp/cloudflare-tunnel-token"

ssh "$ssh_target" "umask 077 && cat > '$remote_token_path'" <<<"$CLOUDFLARE_TUNNEL_TOKEN"

ssh "$ssh_target" "sudo bash -s" <<'EOF'
set -euo pipefail

token_file="/tmp/cloudflare-tunnel-token"

cleanup() {
  rm -f "$token_file"
}

trap cleanup EXIT

if ! command -v cloudflared >/dev/null 2>&1; then
  curl -fsSLo /tmp/cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
  dpkg -i /tmp/cloudflared.deb
  rm -f /tmp/cloudflared.deb
fi

if systemctl list-unit-files cloudflared.service >/dev/null 2>&1; then
  cloudflared service uninstall || true
fi

token="$(cat "$token_file")"
cloudflared service install "$token"
systemctl enable --now cloudflared
systemctl --no-pager --full status cloudflared || true
EOF

echo "cloudflared installed and configured on ${ssh_target}"
