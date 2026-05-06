# Platform Mesh Playground

**Status:** Active
**Maintainers:** Hossein Salahi, Marcel Frizler

---

## 1. Overview

Platform Mesh Playground is a Terraform-managed infrastructure project that provisions a centralized development and integration environment for the Naira project. It deploys a Scaleway VM running a multi-node Kubernetes cluster (Kind with Podman) and bootstraps the full [Platform Mesh](https://github.com/platform-mesh/helm-charts) stack automatically on first boot.

Team members access the environment securely through **Cloudflare WARP** (Zero Trust private networking) rather than exposing Kubernetes or the portal on the public internet. The only public-facing port is SSH (22) for administration.

### Why a Centralized VM Instead of Local Setup

Platform Mesh requires a multi-node Kind cluster with Podman, CoreDNS patching, TLS certificate injection, and Traefik ingress. Replicating this reliably across macOS (Intel + Apple Silicon), Linux, and Windows WSL2 would be a significant maintenance burden. For a small team, a single centralized VM is more practical:

- One environment to maintain, not N laptop variations
- Consistent state across all team members
- Dedicated resources (16 vCPUs / 32 GB RAM) without impacting developer laptops
- Onboarding reduces to: install WARP, receive kubeconfig, connect
- Cross-platform access is provided by the WARP client, not by running the cluster locally

---

## 2. Architecture

```
                        +---------------------------+
                        |       Developer Laptop    |
                        |  (macOS / Linux / WSL2)   |
                        |                           |
                        |  Cloudflare WARP client   |
                        |  kubectl + team kubeconfig|
                        +-------------|-------------+
                                      |
                              Cloudflare WARP
                           (private /32 route)
                                      |
         +----------------------------|------------------------------+
         |                  Scaleway VPC (fr-par)                    |
         |                                                           |
         |   +---------------------------------------------------+   |
         |   |          Debian Bookworm VM (POP2-HC-16C-32G)     |   |
         |   |                                                   |   |
         |   |   cloudflared tunnel  <-- Cloudflare Tunnel       |   |
         |   |                                                   |   |
         |   |   Kind Cluster (Podman provider)                  |   |
         |   |   +-------------------------------------------+   |   |
         |   |   | Control Plane Node                        |   |   |
         |   |   |   API Server :6443 (private IP in SANs)   |   |   |
         |   |   |   CoreDNS (patched for base domain)       |   |   |
         |   |   +-------------------------------------------+   |   |
         |   |   | Worker Node 1          (label: stateful)  |   |   |
         |   |   |   Keycloak, OpenFGA, PostgreSQL           |   |   |
         |   |   +-------------------------------------------+   |   |
         |   |   | Worker Node 2                             |   |   |
         |   |   |   Application workloads                   |   |   |
         |   |   +-------------------------------------------+   |   |
         |   |   | Traefik Ingress        :8443 (portal)     |   |   |
         |   |   |   ClusterIP: 10.96.188.4 (pinned)         |   |   |
         |   |   +-------------------------------------------+   |   |
         |   +---------------------------------------------------+   |
         |                                                           |
         +-----------------------------------------------------------+

         Cloudflare Zero Trust
         +-----------------------------------------------------------+
         |  Tunnel Route:     <private-IP>/32                        |
         |  Access Policy:    team emails / domains / groups         |
         |  Private Apps:     :6443 (K8s API), :8443 (Portal)       |
         |  WARP Profile:     team-scoped, include VM route          |
         |  Device Enrollment: WARP app (optional, Terraform-managed)|
         +-----------------------------------------------------------+
```

---

## 3. Infrastructure Components

### 3.1 Scaleway Resources

| Resource | Description |
|---|---|
| `scaleway_vpc_private_network.pn` | Private VPC network (`platform-mesh-priv-net`) for internal routing |
| `scaleway_instance_ip.public` | Public IPv4 address for SSH administration |
| `scaleway_instance_security_group.ssh_only` | Firewall: inbound SSH (TCP/22) from `ssh_allowed_cidr`, ICMP from anywhere; all other inbound dropped |
| `scaleway_instance_server.vm` | Debian Bookworm VM (default: `POP2-HC-16C-32G`, 100 GB SBS root volume) with cloud-init bootstrap |

### 3.2 Cloudflare Zero Trust Resources

All Cloudflare resources are conditional — they are only created when `cloudflare_account_id` is provided.

| Resource | Condition | Description |
|---|---|---|
| `cloudflare_zero_trust_tunnel_cloudflared_route.vm` | `account_id` + `tunnel_id` set | Private `/32` route through the Cloudflare Tunnel for the VM's private IP |
| `cloudflare_zero_trust_access_policy.team` | Team selectors provided | Allow policy matching team emails, email domains, and/or Access group IDs |
| `cloudflare_zero_trust_access_application.device_enrollment` | Team selectors + `manage_device_enrollment = true` | WARP enrollment application for team device registration |
| `cloudflare_zero_trust_access_application.private_apps` | Team selectors + `manage_private_app_access = true` | Two private apps protecting TCP :6443 (K8s API) and :8443 (Portal), WARP-authenticated |
| `cloudflare_zero_trust_device_custom_profile.team` | Team selectors + `manage_team_warp_profile = true` | Custom WARP device profile that routes the VM private IP through WARP with Split Tunnel Include mode |
| `cloudflare_zero_trust_organization.current` | `manage_zero_trust_organization = true` | Account-level WARP auth session duration setting |

### 3.3 Terraform State Backend

State is stored remotely in Scaleway Object Storage (S3-compatible):

| Setting | Value |
|---|---|
| Bucket | `naira-reply-tf-storage` |
| Key | `simple-vm/terraform.tfstate` |
| Region | `fr-par` |
| Endpoint | `https://s3.fr-par.scw.cloud` |

Scaleway Object Storage does not support state locking. Treat this backend as single-writer and avoid concurrent `terraform apply` runs.

---

## 4. Bootstrap Flow

When the VM boots for the first time, cloud-init executes `bootstrap-platform-mesh`. The script is idempotent — each stage is tracked by marker files under `/var/log/platform-mesh-bootstrap.d/` and skipped on subsequent runs.

```
 cloud-init
    |
    v
 install_cloudflared          -- installs + registers cloudflared tunnel service
    |
    v
 install_bootstrap_tools      -- kubectl, kind (v0.31.0), helm (v3.14.3), yq (v4.43.1)
    |                            all with SHA-256 checksum verification
    v
 configure_host_environment   -- shell aliases, podman rootless mode, lingering
    |
    v
 ensure_platform_mesh_root    -- creates /opt/platform-mesh owned by vm_user
    |
    v
 ensure_platform_mesh_repo    -- git clone platform-mesh/helm-charts
    |
    v
 checkout_platform_mesh_repo  -- git checkout <platform_mesh_version>
    |
    v
 patch_kind_config            -- injects private IP into API server SANs,
    |                            binds ports to 0.0.0.0, adds worker nodes
    v
 patch_platform_mesh_*        -- rewrites portal.localhost to base domain,
    |                            sets nodeSelectors, hostAliases
    v
 write_start_script           -- creates ~/start-platform-mesh.sh
    |
    v
 write_team_access_script     -- creates ~/bin/sync-platform-mesh-team-access
    |
    v
 ensure_platform_mesh_started -- runs Platform Mesh local-setup start.sh
    |
    v
 patch_coredns_for_domain     -- adds base domain -> Traefik ClusterIP in CoreDNS
    |
    v
 validate_*                   -- verifies source tree, TLS certs, CoreDNS,
    |                            Traefik ClusterIP, HTTPRoutes, Gateways
    v
 sync_team_access             -- creates service account, RBAC, team kubeconfig
    |
    v
 DONE                         -- writes /var/log/platform-mesh-bootstrap.done
```

**Logs:** All bootstrap output goes to `/var/log/platform-mesh-bootstrap.log`.

### Key Bootstrap Behaviors

- **Idempotent stages:** Each major stage writes a `.done` marker. Re-running the bootstrap skips completed stages.
- **Internet connectivity wait:** Up to 60 seconds of retry before proceeding.
- **Private IP detection:** Scans `hostname -I` output for RFC 1918 addresses with a 60-second retry loop.
- **Pinned Traefik ClusterIP:** `10.96.188.4` — hardcoded and validated post-bootstrap. Must match the Platform Mesh CR.
- **Domain rewriting:** If `platform_mesh_base_domain` differs from `portal.localhost`, all references in the Platform Mesh `local-setup/` tree are rewritten with `sed`.
- **Certificate validation:** Verifies that the mkcert certificate covers the configured base domain and does not contain stale `portal.localhost` entries.

---

## 5. Security Model

### Network Security

| Port | Protocol | Access | Purpose |
|---|---|---|---|
| 22 | TCP | `ssh_allowed_cidr` only | SSH administration (admin only) |
| 6443 | TCP | Cloudflare WARP only | Kubernetes API server |
| 8443 | TCP | Cloudflare WARP only | Platform Mesh portal (Traefik) |
| ICMP | ICMP | Public | Ping / diagnostics |
| All other inbound | * | Dropped | Default deny |

### Identity and Access

| Layer | Mechanism |
|---|---|
| Network access | Cloudflare WARP enrollment required; traffic routed through encrypted tunnel |
| Application access | Cloudflare Access policies scoped to team emails, email domains, or Access groups |
| Kubernetes RBAC (admin) | Full cluster-admin via VM user's `~/.kube/config` — SSH required |
| Kubernetes RBAC (team) | Dedicated `platform-mesh-team` service account with `admin` role in non-system namespaces; cluster-wide CRD access; no node API or system namespace access |

### Sensitive Data

| Item | Location | Protection |
|---|---|---|
| Cloudflare Tunnel token | Terraform state, VM cloud-init user-data | Marked `sensitive` in Terraform; should be passed via `TF_VAR_cloudflare_tunnel_token`, never committed to `.tfvars` |
| SSH private key | Operator's local machine | Never stored in the repo; only the public key is in `dev.tfvars` |
| Team kubeconfig | VM at `~/.kube/platform-mesh-team.kubeconfig` | `chmod 0600`; distributed by admin via `scp` |
| Admin kubeconfig | VM at `~/.kube/config` | Requires SSH to the VM |
| Terraform state | Scaleway Object Storage (`naira-reply-tf-storage`) | Restrict bucket access; contains tunnel token and infrastructure secrets |

---

## 6. Prerequisites

### For Administrators (deploying/managing the VM)

| Tool | Purpose |
|---|---|
| Terraform >= 1.6 | Infrastructure provisioning |
| Scaleway CLI or API credentials | `SCW_ACCESS_KEY`, `SCW_SECRET_KEY` for Terraform provider and S3 backend |
| Cloudflare API token | Must have permissions for: Zero Trust apps, policies, devices, tunnels |
| SSH key pair | Ed25519 recommended; public key goes into `ssh_public_key` variable |

### For Team Members (using the environment)

| Tool | Purpose |
|---|---|
| [Cloudflare WARP client](https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/download-warp/) | Private network access to the VM |
| `kubectl` | Kubernetes interaction via team kubeconfig |
| (Optional) `mkcert` root CA | Trust the portal TLS certificate locally |

---

## 7. Deployment Guide

### 7.1 Bootstrap the State Backend (first time only)

```bash
cd ../tfstate-bootstrap
terraform init
terraform apply -var='bucket_name=naira-reply-tf-storage'
cd ../simple-vm
```

An example backend configuration file is provided at `scaleway.s3.tfbackend.example`. Copy it to a path outside version control (any `*.tfbackend` or `*.hcl` file is gitignored) and adjust the values for your environment.

### 7.2 Configure Credentials

```bash
# Scaleway — for both the provider and S3 backend
export SCW_ACCESS_KEY="<your-access-key>"
export SCW_SECRET_KEY="<your-secret-key>"
export AWS_ACCESS_KEY_ID="$SCW_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$SCW_SECRET_KEY"

# Cloudflare
export CLOUDFLARE_API_TOKEN="<your-api-token>"

# Tunnel token (sensitive — never put in .tfvars)
export TF_VAR_cloudflare_tunnel_token="<tunnel-token>"
```

### 7.3 Configure Variables

Edit `dev.tfvars` with your local values:

```hcl
ssh_public_key   = "ssh-ed25519 AAAA..."
ssh_allowed_cidr = "203.0.113.10/32"          # your current public IP

cloudflare_account_id = "<account-id>"
cloudflare_tunnel_id  = "<tunnel-uuid>"

cloudflare_team_email_domains = ["company.com"]
cloudflare_team_emails        = ["alice@company.com", "bob@company.com"]

# Optional overrides
# cloudflare_manage_device_enrollment       = true
# cloudflare_manage_zero_trust_organization = true
# platform_mesh_base_domain                 = "portal.example.com"
# platform_mesh_version                     = "0.2.0"
```

`dev.tfvars` is in `.gitignore` and should never be committed.

### 7.4 Initialize and Apply

```bash
terraform init -reconfigure -backend-config=scaleway.s3.tfbackend
terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```

### 7.5 Monitor Bootstrap Progress

```bash
ssh naira@$(terraform output -raw public_ip) "tail -f /var/log/platform-mesh-bootstrap.log"
```

Bootstrap completes when you see:

```
Platform Mesh cluster provisioned and ready!
```

### 7.6 Verify Deployment

```bash
# Check Terraform outputs
terraform output

# Test SSH connectivity
ssh naira@$(terraform output -raw public_ip) "kubectl get nodes"
```

Expected output: 3 nodes (1 control-plane, 2 workers) in `Ready` state.

---

## 8. CI/CD Pipeline

A GitHub Actions workflow (`.github/workflows/terraform.yml`) automates Terraform operations:

| Trigger | Job | What it does |
|---|---|---|
| Pull request (`.tf` or workflow changes) | **plan** | `fmt -check`, `validate`, `plan`; posts the plan as a PR comment |
| Push to `main` (`.tf` or workflow changes) | **apply** | `fmt -check`, `validate`, `plan`, `apply -auto-approve` |

### Concurrency

- **Plan jobs** use a per-branch concurrency group (`terraform-plan-<branch>`); a new push cancels any in-flight plan for the same branch.
- **Apply jobs** use a repo-wide concurrency group (`terraform-state-<repo>`) with `cancel-in-progress: false`, so only one apply runs at a time (compensating for the lack of native state locking in Scaleway S3).

### Required Secrets and Variables

Configure these in the GitHub repository settings, or use the helper script:

```bash
./scripts/setup-github-secrets.sh
```

The script reads values from your environment and populates them via the `gh` CLI.

**Secrets:**

| Secret | Required | Description |
|---|---|---|
| `SCW_ACCESS_KEY` | Yes | Scaleway API access key |
| `SCW_SECRET_KEY` | Yes | Scaleway API secret key |
| `SCW_DEFAULT_PROJECT_ID` | Yes | Scaleway default project ID |
| `CLOUDFLARE_API_TOKEN` | Yes | Cloudflare API token with Zero Trust permissions |
| `TF_STATE_ACCESS_KEY` | No | State backend access key (defaults to `SCW_ACCESS_KEY`) |
| `TF_STATE_SECRET_KEY` | No | State backend secret key (defaults to `SCW_SECRET_KEY`) |
| `TF_VAR_SSH_PUBLIC_KEY` | Yes | SSH public key for the VM user |
| `TF_VAR_SSH_ALLOWED_CIDR` | Yes | CIDR allowed to reach SSH |
| `TF_VAR_CLOUDFLARE_TUNNEL_TOKEN` | No | Cloudflare Tunnel token |
| `TF_VAR_CLOUDFLARE_ACCOUNT_ID` | No | Cloudflare account ID |
| `TF_VAR_CLOUDFLARE_TUNNEL_ID` | No | Cloudflare Tunnel UUID |
| `TF_VAR_CLOUDFLARE_TEAM_EMAIL_DOMAINS` | No | JSON array of allowed email domains |
| `TF_VAR_CLOUDFLARE_TEAM_EMAILS` | No | JSON array of allowed emails |

**Repository Variables:**

| Variable | Description |
|---|---|
| `TF_STATE_BUCKET` | S3 bucket name for Terraform state |
| `TF_STATE_KEY` | Object key for the state file |
| `TF_STATE_REGION` | S3 region (e.g., `fr-par`) |
| `TF_STATE_S3_ENDPOINT` | S3-compatible endpoint URL |

---

## 9. Team Onboarding Guide

This section is intended for team members who need access to the environment. No SSH or Terraform access is required.

### Step 1 — Install Cloudflare WARP

Download and install the [Cloudflare WARP client](https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/download-warp/) for your platform.

### Step 2 — Enroll Your Device

Open the WARP client and enroll in the organization's Zero Trust tenant. Use your team email address when prompted. After enrollment, toggle WARP to **Connected**.

### Step 3 — Receive Kubeconfig from Admin

An administrator will securely send you the file `platform-mesh-team.kubeconfig`. Save it to a known location on your machine, for example `~/.kube/platform-mesh-team.kubeconfig`.

Admins generate and distribute this file by running:

```bash
./scripts/setup-team-access.sh
# or
./scripts/onboarding.sh   # prints copy commands
```

### Step 4 — Trust the Portal Certificate

The portal uses a self-signed certificate generated by `mkcert` on the VM. To avoid browser warnings:

1. Ask an admin for the root CA file (`platform-mesh-rootCA.pem`).
2. Import it into your OS trust store:
   - **macOS:** `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain platform-mesh-rootCA.pem`
   - **Linux (Debian/Ubuntu):** `sudo cp platform-mesh-rootCA.pem /usr/local/share/ca-certificates/platform-mesh-rootCA.crt && sudo update-ca-certificates`
   - **Windows:** Double-click the `.pem` file and install to "Trusted Root Certification Authorities"

### Step 5 — Access the Portal

**If the base domain is `portal.localhost` (default):**

Start a local port-forward:

```bash
kubectl --kubeconfig ./platform-mesh-team.kubeconfig \
  -n default port-forward svc/traefik 8443:8443
```

Then open: `https://portal.localhost:8443`

The portal is only reachable while the port-forward session is running. No `/etc/hosts` entry is needed — `portal.localhost` resolves to `127.0.0.1` by default on most systems.

**If a custom base domain is configured:**

Add a hosts entry on your workstation:

```
<private-ip>  <base-domain>
```

Then open: `https://<base-domain>:8443`

### Step 6 — Use kubectl

```bash
export KUBECONFIG=~/.kube/platform-mesh-team.kubeconfig
kubectl get namespaces
kubectl get pods -n default
```

### What You Can and Cannot Do

| Allowed | Not allowed |
|---|---|
| List namespaces | Access `kube-system`, `kube-public`, `kube-node-lease` |
| Create / update / delete resources in application namespaces | Access Kubernetes node API |
| Read/write CustomResourceDefinitions (cluster-wide) | Manage cluster-level RBAC |

---

## 10. Configuration Reference

### Infrastructure Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `vm_user` | `string` | `"naira"` | Linux user created on the VM |
| `ssh_public_key` | `string` | *required* | SSH public key for the VM user |
| `ssh_allowed_cidr` | `string` | *required* | CIDR allowed to reach SSH (e.g., `203.0.113.10/32`) |
| `platform_mesh_version` | `string` | `"0.2.0"` | Git ref from `platform-mesh/helm-charts` to deploy |
| `platform_mesh_base_domain` | `string` | `"portal.localhost"` | Base domain for the portal and subdomains |
| `cloudflare_tunnel_token` | `string` | `null` | Cloudflare Tunnel token (sensitive) |
| `scaleway_instance_type` | `string` | `"POP2-HC-16C-32G"` | Scaleway instance type |
| `scaleway_instance_image` | `string` | `"debian_bookworm"` | Scaleway OS image |
| `scaleway_root_volume_size_gb` | `number` | `100` | Root disk size in GiB (min: 20) |
| `scaleway_instance_tags` | `list(string)` | `["platform-mesh", "simple-vm"]` | VM tags |

### Cloudflare Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `cloudflare_account_id` | `string` | `null` | Cloudflare account ID. Enables all Zero Trust resources when set. |
| `cloudflare_tunnel_id` | `string` | `null` | Existing tunnel UUID. Required with `account_id` to create the private route. |
| `cloudflare_team_email_domains` | `list(string)` | `[]` | Domains allowed in Access policies (e.g., `["company.com"]`) |
| `cloudflare_team_emails` | `list(string)` | `[]` | Specific emails allowed in Access policies and WARP profile match |
| `cloudflare_team_access_group_ids` | `list(string)` | `[]` | Existing Access group IDs for policies and WARP profile match |
| `cloudflare_allowed_idp_ids` | `list(string)` | `[]` | IdP IDs for enrollment and private apps. Empty = all configured IdPs. |
| `cloudflare_access_policy_session_duration` | `string` | `"24h"` | Session duration for Access policy and private apps |
| `cloudflare_manage_zero_trust_organization` | `bool` | `false` | Manage account-level WARP auth session setting |
| `cloudflare_warp_auth_session_duration` | `string` | `"24h"` | Account-level WARP auth session duration |
| `cloudflare_manage_device_enrollment` | `bool` | `true` | Manage the WARP enrollment application |
| `cloudflare_manage_private_app_access` | `bool` | `true` | Manage private Access apps for K8s API and portal |
| `cloudflare_manage_team_warp_profile` | `bool` | `true` | Manage a team-scoped WARP device profile |
| `cloudflare_warp_profile_match` | `string` | `null` | Override for WARP profile match expression |
| `cloudflare_warp_profile_name` | `string` | `"Platform Mesh team"` | Name of the custom WARP profile |
| `cloudflare_warp_profile_precedence` | `number` | `100` | WARP profile precedence (lower wins) |
| `cloudflare_warp_profile_include_extra_cidrs` | `list(string)` | `[]` | Extra CIDRs for the WARP profile |
| `cloudflare_warp_profile_include_extra_hosts` | `list(string)` | `[]` | Extra hostnames for the WARP profile (IdP hosts, team domain) |

### Terraform Outputs

| Output | Description |
|---|---|
| `public_ip` | VM public IP address (for SSH) |
| `private_ip` | VM private IP address (used in WARP route and kubeconfig) |
| `warp_portal_url` | Full portal URL (e.g., `https://portal.localhost:8443`) |
| `warp_private_route_cidr` | CIDR routed through WARP (`<private-ip>/32`) |
| `admin_warp_kubeconfig_command` | One-liner to download and patch the admin kubeconfig for WARP access |

---

## 11. Operational Runbook

### Checking Bootstrap Status

```bash
# Is bootstrap complete?
ssh naira@<PUBLIC_IP> "cat /var/log/platform-mesh-bootstrap.done"

# View full bootstrap log
ssh naira@<PUBLIC_IP> "cat /var/log/platform-mesh-bootstrap.log"

# Which stages have completed?
ssh naira@<PUBLIC_IP> "ls /var/log/platform-mesh-bootstrap.d/"
```

### Restarting Platform Mesh

If the Kind cluster is down after a VM reboot:

```bash
ssh naira@<PUBLIC_IP>
sudo -u naira bash ~/start-platform-mesh.sh
```

### Re-running Bootstrap

The bootstrap is idempotent. To force a full re-run:

```bash
ssh naira@<PUBLIC_IP>
sudo rm -f /var/log/platform-mesh-bootstrap.done
sudo rm -rf /var/log/platform-mesh-bootstrap.d/
sudo /usr/local/bin/bootstrap-platform-mesh
```

### Updating Platform Mesh Version

1. Change `platform_mesh_version` in `dev.tfvars`.
2. `terraform apply -var-file=dev.tfvars` — this will not re-run cloud-init on an existing VM (cloud-init changes are ignored via `lifecycle { ignore_changes }`).
3. SSH into the VM and re-run the bootstrap manually:

```bash
ssh naira@<PUBLIC_IP>
sudo rm -f /var/log/platform-mesh-bootstrap.done
sudo rm -rf /var/log/platform-mesh-bootstrap.d/
# Update the version in the bootstrap script or re-checkout manually:
cd /opt/platform-mesh/helm-charts
git fetch --tags --force
git checkout <new-version>
sudo /usr/local/bin/bootstrap-platform-mesh
```

### Adding New Team Members

1. Add their email to `cloudflare_team_emails` in `dev.tfvars`.
2. `terraform apply -var-file=dev.tfvars` to update Access policies and WARP profile.
3. Have them follow the Team Onboarding Guide (Section 9).
4. Distribute the existing team kubeconfig — no server-side changes needed.

### Adding New Namespaces

After new namespaces appear in the cluster, re-sync RBAC:

```bash
./scripts/setup-team-access.sh
```

This re-runs the team access script, which creates RoleBindings in all non-system namespaces.

### Rotating the Cloudflare Tunnel Token

1. Generate a new token in the Cloudflare dashboard.
2. Re-apply with the new token:

```bash
TF_VAR_cloudflare_tunnel_token="<new-token>" terraform apply -var-file=dev.tfvars
```

3. SSH into the VM and restart cloudflared:

```bash
ssh naira@<PUBLIC_IP> "sudo systemctl restart cloudflared"
```

Note: Cloud-init changes are ignored on existing VMs, so the new token only takes effect if you reinstall cloudflared manually or recreate the VM.

### Changing the SSH Allowed CIDR

When your public IP changes:

1. Update `ssh_allowed_cidr` in `dev.tfvars`.
2. `terraform apply -var-file=dev.tfvars` — this updates the security group immediately.

### Destroying the Environment

```bash
terraform destroy -var-file=dev.tfvars
```

This removes all Scaleway and Cloudflare resources. The S3 state backend bucket is managed separately and is not affected.

---

## 12. Scripts Reference

| Script | Run From | Purpose |
|---|---|---|
| `scripts/onboarding.sh` | Operator workstation | Prints team onboarding instructions derived from current Terraform outputs |
| `scripts/setup-team-access.sh` | Operator workstation | SSHs into the VM, creates/updates the team service account, RBAC bindings, and team kubeconfig, then copies the kubeconfig locally |
| `scripts/setup-github-secrets.sh` | Operator workstation | Populates GitHub Actions secrets and repository variables for the CI/CD pipeline via the `gh` CLI |
| `bootstrap.sh.tftpl` | VM (via cloud-init) | Full VM bootstrap: tool installation, Platform Mesh deployment, cluster configuration, validation |

---

## 13. Design Decisions

| Decision | Rationale |
|---|---|
| **Centralized VM over local setup** | Platform Mesh's complexity (multi-node Kind, CoreDNS patches, TLS injection) makes reliable cross-platform local reproduction a maintenance burden. A shared VM with WARP access is simpler for a small team. |
| **Kind with Podman** (not Docker) | Runs rootless without Docker Engine; better suited for Debian server environments. |
| **Cloudflare WARP** (not VPN/SSH tunnel) | Zero Trust identity-aware access; no need to manage VPN infrastructure; per-user audit trail; Split Tunnel keeps non-work traffic off the tunnel. |
| **Terraform over Makefile** | Terraform is the natural task runner for this infrastructure project. Adding `make` would be an indirection layer without benefit. Helper scripts cover operational tasks. |
| **No DevContainer** | No local build step or service to run. Editor tooling is lightweight enough for individual setup. |
| **Idempotent bootstrap with stage markers** | Allows safe re-runs after partial failures without repeating expensive steps (cluster creation, tool downloads). |
| **Team kubeconfig via service account** | Scoped RBAC without distributing SSH access. Admins control distribution; team members cannot escalate privileges. |
| **cloud-init `ignore_changes`** | Cloud-init is consumed on first boot only. Ignoring drift avoids Terraform wanting to recreate the VM on every apply when the bootstrap script changes. |
| **Pinned tool versions with checksums** | Ensures reproducible builds. Kind v0.31.0, Helm v3.14.3, yq v4.43.1 — all verified with SHA-256 before installation. |

---

## 14. Troubleshooting

### Bootstrap never completes

**Check:** `ssh naira@<PUBLIC_IP> "tail -50 /var/log/platform-mesh-bootstrap.log"`

Common causes:
- **No internet:** The script retries for 60 seconds. Check the Scaleway console for network issues.
- **Private IP not assigned:** The VPC interface may take time. The script retries for 60 seconds.
- **Platform Mesh start.sh fails:** Check Kind/Podman status: `ssh naira@<PUBLIC_IP> "systemctl --user status podman.socket"` and `kind get clusters`.

### kubectl cannot reach the cluster over WARP

1. Verify WARP is connected (green icon in the system tray).
2. Confirm the route is active: `curl -v https://<private-ip>:6443 --insecure` should return a TLS handshake (even if unauthorized).
3. Check the WARP profile includes the VM's `/32` route: `terraform output warp_private_route_cidr`.
4. If using Split Tunnel Include mode, ensure your IdP and Cloudflare team domain are listed in `cloudflare_warp_profile_include_extra_hosts`.

### TLS certificate errors when connecting to the K8s API

The bootstrap injects the VM's private IP into the API server's certificate SANs. If you see `x509: certificate is valid for X, not Y`:
- The private IP may have changed (rare with Scaleway VPC). Check `terraform output private_ip` vs. the kubeconfig server address.
- Re-run bootstrap to regenerate certificates.

### Portal returns 502 or is unreachable

1. Check Traefik is running: `kubectl get pods -n default | grep traefik`
2. Check the portal service: `kubectl get svc traefik -n default` — ClusterIP should be `10.96.188.4`.
3. Check CoreDNS has the domain entry: `kubectl -n kube-system get configmap coredns -o yaml | grep <base-domain>`.

### Terraform plan shows changes to cloud_init

This is expected if you changed any variable that feeds into the bootstrap template. The `lifecycle { ignore_changes = [cloud_init] }` block prevents Terraform from recreating the VM. The change is informational only and will not be applied.

### Cloudflare "only one WARP enrollment app" error

Cloudflare allows only one WARP enrollment application per account. Set `cloudflare_manage_device_enrollment = false` (default) and manage enrollment in the Cloudflare dashboard instead.

---

## 15. File Structure

```
.
├── .github/
│   └── workflows/
│       └── terraform.yml             # GitHub Actions: plan on PR, apply on main
├── backend.tf                        # S3 backend declaration
├── bootstrap.sh.tftpl                # VM bootstrap script (Terraform template)
├── cloud-init.yml                    # Cloud-init configuration (Terraform template)
├── cloudflare-access.tf              # Zero Trust: org, policies, enrollment, private apps, WARP profile
├── cloudflare-route.tf               # Cloudflare Tunnel private route
├── dev.tfvars                        # Local development variables (gitignored)
├── locals.tf                         # Computed values: IPs, CIDR, policy includes, feature flags
├── outputs-infra.tf                  # Terraform outputs
├── providers.tf                      # Provider configuration (Cloudflare, Scaleway)
├── scaleway.s3.tfbackend             # S3 backend configuration for Scaleway Object Storage (gitignored)
├── scaleway.s3.tfbackend.example     # Example backend configuration (committed)
├── scaleway.tf                       # Scaleway: VPC, IP, security group, VM instance
├── scripts/
│   ├── onboarding.sh                 # Print team onboarding instructions
│   ├── setup-github-secrets.sh       # Populate GitHub Actions secrets/variables via gh CLI
│   └── setup-team-access.sh          # Create/update team RBAC and kubeconfig
├── validations.tf                    # Input validation checks
├── variables-cloudflare.tf           # Cloudflare variable declarations
├── variables-infra.tf                # Infrastructure variable declarations
└── versions.tf                       # Required providers and Terraform version
```
