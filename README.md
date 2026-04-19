# Platform Mesh VM on Scaleway

This repository provisions a Debian VM on Scaleway and bootstraps the Platform Mesh local setup automatically on first boot.

The VM keeps Platform Mesh bound to the VM's local loopback interface and exposes only SSH publicly. That matches the upstream `portal.localhost` access model more closely than the previous Tailscale-based approach and avoids exposing the local development stack directly on the internet.

## What Terraform Provisions

- A Scaleway public IP
- A security group that allows SSH only
- A Debian Bookworm VM
- A cloud-init bootstrap that installs Podman, `kubectl`, `kind`, `helm`, `mkcert`, and the supporting CLI tools
- An automated checkout of `platform-mesh/helm-charts` at `0.2.0`
- A ready-to-run launcher script for Platform Mesh using Podman after login

## Required Inputs

- `ssh_public_key`: SSH public key for the VM user

## Optional Inputs

- `vm_user`: Linux user created on the VM. Defaults to `naira`
- `ssh_allowed_cidr`: CIDR allowed to reach SSH. Defaults to `0.0.0.0/0`
- `platform_mesh_version`: Git ref to deploy from `platform-mesh/helm-charts`. Defaults to `0.2.0`

## Usage

1. Initialize Terraform:

   ```bash
   terraform init
   ```

2. Apply the configuration with your SSH public key:

   ```bash
   terraform apply -var='ssh_public_key=ssh-ed25519 AAAA...'
   ```

3. Wait for cloud-init to finish. The first boot installs tools, prepares the checkout, and writes the launch helper.

4. Connect to the VM:

   ```bash
   ssh <vm-user>@<public-ip>
   ```

5. Start Platform Mesh from the VM shell:

   ```bash
   ~/start-platform-mesh.sh
   ```

6. Tunnel the portal back to your workstation:

   ```bash
   ssh -L 8443:127.0.0.1:8443 <vm-user>@<public-ip>
   ```

7. Open the portal locally:

   ```text
   https://portal.localhost:8443
   ```

## Operational Notes

- Bootstrap logs are written to `/var/log/platform-mesh-bootstrap.log`.
- The Platform Mesh checkout lives at `/opt/platform-mesh/helm-charts` and is owned by `<vm-user>`.
- The launcher script is written to `/home/<vm-user>/start-platform-mesh.sh`.
- The shell profile is written to `/home/<vm-user>/.platform-mesh-shell.rc` and sourced from `.bashrc`. It provides `kubectl` completion, the `k` alias, `KIND_EXPERIMENTAL_PROVIDER=podman`, and the `pm-admin` alias.
- `yq` is installed as the standalone binary in `/usr/local/bin/yq`.
- The upstream local setup generates its own `mkcert` CA on the VM. Your browser may warn until you copy and trust `/home/<vm-user>/.local/share/mkcert/rootCA.pem` on your workstation.
- The admin kubeconfig created by the setup is available under `local-setup/.secret/kcp/admin.kubeconfig` inside the cloned repository.
