#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
caller_pwd="$PWD"

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

require_output "admin_warp_kubeconfig_command"
require_output "public_ip"
require_output "private_ip"

admin_warp_kubeconfig_command="$(output_raw "admin_warp_kubeconfig_command")"
public_ip="$(output_raw "public_ip")"
private_ip="$(output_raw "private_ip")"
vm_user="$(printf '%s\n' "$admin_warp_kubeconfig_command" | sed -nE 's#^scp ([^@[:space:]]+)@[^:]+:.*#\1#p')"

if [[ -z "$vm_user" ]]; then
  vm_user="$(printf '%s\n' "$admin_warp_kubeconfig_command" | sed -nE 's#.*:/home/([^/]+)/\.kube/config.*#\1#p')"
fi

if [[ -z "$vm_user" ]]; then
  echo "Unable to derive the VM user from admin_warp_kubeconfig_command" >&2
  exit 1
fi

ssh_target="${vm_user}@${public_ip}"
remote_kubeconfig_path="/home/${vm_user}/.kube/platform-mesh-team.kubeconfig"
local_kubeconfig_path="${caller_pwd}/platform-mesh-team.kubeconfig"

ssh "$ssh_target" "PRIVATE_IP='$private_ip' bash -s" <<'EOF'
set -euo pipefail

admin_kubeconfig="$HOME/.kube/config"
team_kubeconfig="$HOME/.kube/platform-mesh-team.kubeconfig"
service_account_namespace="default"
service_account_name="platform-mesh-team"
token_secret_name="platform-mesh-team-token"
rolebinding_name="platform-mesh-team-admin"
legacy_rolebinding_name="platform-mesh-team-edit"
role_name="admin"
cluster_role_name="platform-mesh-team-namespace-reader"
cluster_role_binding_name="platform-mesh-team-namespace-reader"
excluded_namespace_pattern='^(kube-system|kube-public|kube-node-lease)$'

kubectl_admin() {
  kubectl --kubeconfig "$admin_kubeconfig" "$@"
}

kubectl_admin -n "$service_account_namespace" create serviceaccount "$service_account_name" --dry-run=client -o yaml | kubectl_admin apply -f -

cat <<MANIFEST | kubectl_admin apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: $token_secret_name
  namespace: $service_account_namespace
  annotations:
    kubernetes.io/service-account.name: $service_account_name
type: kubernetes.io/service-account-token
MANIFEST

cat <<MANIFEST | kubectl_admin apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: $cluster_role_name
rules:
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list"]
  - apiGroups: ["apiextensions.k8s.io"]
    resources: ["customresourcedefinitions"]
    verbs: ["*"]
MANIFEST

cat <<MANIFEST | kubectl_admin apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: $cluster_role_binding_name
subjects:
  - kind: ServiceAccount
    name: $service_account_name
    namespace: $service_account_namespace
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: $cluster_role_name
MANIFEST

while IFS= read -r namespace; do
  if [[ "$namespace" =~ $excluded_namespace_pattern ]]; then
    kubectl_admin -n "$namespace" delete rolebinding "$rolebinding_name" --ignore-not-found
    kubectl_admin -n "$namespace" delete rolebinding "$legacy_rolebinding_name" --ignore-not-found
    continue
  fi

  cat <<MANIFEST | kubectl_admin apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: $rolebinding_name
  namespace: $namespace
subjects:
  - kind: ServiceAccount
    name: $service_account_name
    namespace: $service_account_namespace
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: $role_name
MANIFEST

  kubectl_admin -n "$namespace" delete rolebinding "$legacy_rolebinding_name" --ignore-not-found
done < <(kubectl_admin get namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

token_b64=""
for _ in {1..30}; do
  token_b64="$(kubectl_admin -n "$service_account_namespace" get secret "$token_secret_name" -o jsonpath='{.data.token}' 2>/dev/null || true)"
  if [[ -n "$token_b64" ]]; then
    break
  fi
  sleep 1
done

if [[ -z "$token_b64" ]]; then
  echo "Timed out waiting for team service account token secret" >&2
  exit 1
fi

ca_data="$(kubectl_admin config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
token="$(printf '%s' "$token_b64" | base64 --decode)"

cat >"$team_kubeconfig" <<KUBECONFIG
apiVersion: v1
kind: Config
clusters:
  - cluster:
      certificate-authority-data: $ca_data
      server: https://$PRIVATE_IP:6443
    name: platform-mesh
contexts:
  - context:
      cluster: platform-mesh
      namespace: default
      user: platform-mesh-team
    name: platform-mesh-team
current-context: platform-mesh-team
users:
  - name: platform-mesh-team
    user:
      token: $token
KUBECONFIG

chmod 0600 "$team_kubeconfig"
EOF

scp "${ssh_target}:${remote_kubeconfig_path}" "$local_kubeconfig_path"

cat <<EOF
Restricted team kubeconfig created and copied to:
  $local_kubeconfig_path

This kubeconfig uses a dedicated service account bound to the built-in admin role
in non-system namespaces, allowing users to add, edit, and delete resources.
It also grants cluster-wide access to CustomResourceDefinitions (CRDs).
It does not grant Kubernetes node API access or access to system namespaces.
EOF
