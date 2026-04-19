# Platform Mesh VM on Scaleway

This repository provisions a Debian VM on Scaleway and bootstraps the Platform Mesh local setup automatically on first boot. 

The infrastructure is optimized for secure, direct access via **Cloudflare WARP**, allowing you to interact with the Kubernetes API and the Onboarding Portal without SSH tunnels or "insecure" TLS flags.

## What Terraform Provisions

- A Scaleway public IP and Private VPC interface.
- A security group that allows SSH (22), K8s API (6443), Portal (8443), and ICMP.
- A Debian Bookworm VM with Podman and Kind.
- **Cloudflare Tunnel** integration for Private Network routing.
- **Dynamic Certificate Injection**: The bootstrap script automatically detects the VM's private IP and injects it into the Kubernetes API server's certificate SANs, ensuring full TLS trust over WARP.

## Required Inputs

- `ssh_public_key`: SSH public key for the VM user.
- `cloudflare_tunnel_token`: The token for your pre-configured Cloudflare Tunnel.

## Optional Inputs

- `vm_user`: Linux user created on the VM. Defaults to `naira`.
- `ssh_allowed_cidr`: CIDR allowed to reach SSH. Defaults to `0.0.0.0/0`.
- `platform_mesh_version`: Git ref to deploy from `platform-mesh/helm-charts`. Defaults to `0.2.0`.

## Setup & Usage

### 1. Cloudflare Dashboard Configuration
Before applying, ensure your Cloudflare Zero Trust dashboard is configured:
- **Tunnel Route**: Add a Private Network route for `172.16.0.0/22` (or the specific VM IP) to your tunnel.
- **Split Tunneling**: Ensure your WARP client settings include the `172.16.x.x` range.

### 2. Deploy
```bash
terraform apply \
  -var="ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)" \
  -var="cloudflare_tunnel_token=your_token_here"
```

### 3. Connect via Cloudflare WARP

Once the bootstrap finishes (check `/var/log/platform-mesh-bootstrap.log` on the VM), use the generated helper command from Terraform outputs to set up your local `kubectl`:

```bash
# Example command from 'terraform output warp_kubeconfig_command'
scp naira@<PUBLIC_IP>:/home/naira/.kube/config ./kind.kubeconfig
sed -i '' 's/127.0.0.1:6443/<PRIVATE_IP>:6443/g' ./kind.kubeconfig
export KUBECONFIG=$(pwd)/kind.kubeconfig

# Test direct, secure access (No warnings!)
kubectl get nodes
```

### 4. Access the Portal
To access the onboarding portal at `https://portal.localhost:8443`, add the following to your workstation's `/etc/hosts`:

```text
<PRIVATE_IP>  portal.localhost
```

## Operational Notes

- **Bootstrap Logs**: Monitor progress with `ssh naira@<PUBLIC_IP> "tail -f /var/log/platform-mesh-bootstrap.log"`.
- **Certificates**: The Kubernetes API certificate is automatically generated to trust the VM's private IP.
- **Shell Profile**: Sourced from `.bashrc`, providing `k` alias, `kubectl` completion, and `KIND_EXPERIMENTAL_PROVIDER=podman`.
- **Kind Wrapper**: A wrapper at `~/bin/kind` ensures that internal setup scripts do not overwrite our custom TLS settings.
- **Trusting the Portal**: To trust the portal's browser certificate, run `terraform output mkcert_root_ca_copy_command` and add the PEM to your OS keychain.
