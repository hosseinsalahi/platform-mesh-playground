# Platform Mesh VM on Scaleway

This repository provisions a Debian VM on Scaleway and bootstraps the Platform Mesh local setup automatically on first boot.

The stack is designed for secure team access through **Cloudflare WARP**. The VM keeps SSH public for administration, while the Kubernetes API and portal are intended to be reached through Cloudflare's private network routing instead of public inbound ports.

## What Terraform Provisions

- A Scaleway public IP and Private VPC interface.
- A security group that allows SSH (22) and ICMP only.
- A Debian Bookworm VM with Podman and Kind.
- **Cloudflare Tunnel** integration for Private Network routing.
- An optional Cloudflare-managed private route for the VM when `cloudflare_account_id` and `cloudflare_tunnel_id` are provided.
- Terraform-managed Zero Trust enrollment and private app policies when team selectors are provided.
- **Dynamic Certificate Injection**: The bootstrap script automatically detects the VM's private IP and injects it into the Kubernetes API server's certificate SANs, ensuring full TLS trust over WARP.

## Required Inputs

- `ssh_public_key`: SSH public key for the VM user.
- `ssh_allowed_cidr`: CIDR allowed to reach SSH. Pass a specific admin source range such as `203.0.113.10/32`.

## Optional Inputs

- `vm_user`: Linux user created on the VM. Defaults to `naira`.
- `platform_mesh_version`: Git ref to deploy from `platform-mesh/helm-charts`. Defaults to `0.2.0`.
- `scaleway_instance_type`: Scaleway instance type for the VM. Defaults to `POP2-HC-16C-32G`.
- `scaleway_instance_image`: Scaleway image for the VM. Defaults to `debian_bookworm`.
- `scaleway_root_volume_size_gb`: Root disk size in GiB. Defaults to `100`.
- `scaleway_instance_tags`: Tags applied to the VM. Defaults to `["platform-mesh","simple-vm"]`.
- `cloudflare_account_id`: Cloudflare account ID. When paired with `cloudflare_tunnel_id`, Terraform will create the WARP private route automatically.
- `cloudflare_tunnel_id`: Existing remotely-managed Cloudflare Tunnel UUID.
- `cloudflare_team_email_domains`: Domains allowed to enroll devices and use the private apps.
- `cloudflare_team_emails`: Explicit user emails allowed to enroll devices and use the private apps.
- `cloudflare_team_access_group_ids`: Existing Access group IDs allowed to enroll devices and use the private apps.
- `cloudflare_allowed_idp_ids`: Optional IdP IDs for the enrollment and private apps.
- `cloudflare_manage_zero_trust_organization`: Whether Terraform should manage the account-level WARP auth settings needed for WARP-authenticated private apps. Defaults to `false` to avoid Terraform lifecycle warnings on the persistent Zero Trust organization object.
- `cloudflare_warp_auth_session_duration`: Account-level WARP auth session duration. Defaults to `24h`.
- `cloudflare_manage_team_warp_profile`: Whether Terraform should manage a team-specific WARP profile. Defaults to `true`.
- `cloudflare_warp_profile_match`: Optional custom-profile match expression override. If unset, Terraform derives it from `cloudflare_team_emails` and `cloudflare_team_access_group_ids`.
- `cloudflare_warp_profile_include_extra_hosts`: Extra hostnames required when you enable the custom WARP profile in Split Tunnel Include mode, typically your IdP hostnames and `<team>.cloudflareaccess.com`.

## Setup & Usage

### 1. Cloudflare Dashboard Configuration
Before applying, make sure your Cloudflare Zero Trust tenant is ready for the team:
- Create or reuse a remotely-managed `cloudflared` tunnel for this VM.
- Keep the tunnel token outside your source code. You can pass it securely during apply using the `TF_VAR_cloudflare_tunnel_token` environment variable.
- Export a Cloudflare API token with permission to manage Zero Trust apps, policies, devices, and tunnels.
- If you do not configure team selectors in Terraform, define **device enrollment permissions** and private-network access manually in the dashboard.
- The default portal hostname is `portal.localhost`, which works well with local `kubectl port-forward` access. If you want a clean shared portal hostname instead, publish a Cloudflare private hostname and set `platform_mesh_base_domain` to that DNS name.

If you provide `cloudflare_account_id` and `cloudflare_tunnel_id`, Terraform will create the VM's `/32` private route automatically. If you also provide team selectors, Terraform will create:
- An allow policy for the team.
- The account-level WARP auth session setting required by WARP-authenticated private apps only if `cloudflare_manage_zero_trust_organization=true`.
- A WARP enrollment application only if `cloudflare_manage_device_enrollment=true`.
- Two private Access applications protecting `6443/tcp` and `8443/tcp`.

The team WARP profile is created by default when team selectors are present and `cloudflare_manage_team_warp_profile=true`. Terraform derives the profile match from `cloudflare_team_emails` and `cloudflare_team_access_group_ids`, unless you override it with `cloudflare_warp_profile_match`. The profile uses Split Tunnel Include mode for the VM route and automatically includes your Cloudflare team domain. Add any extra IdP hostnames you need in `cloudflare_warp_profile_include_extra_hosts`.

Cloudflare Access policies support domain-based selectors, but the WARP device-profile match used here should be based on exact emails, group IDs, or an explicit `cloudflare_warp_profile_match` override. If you only pass `cloudflare_team_email_domains`, Terraform can still create the Access policy, but it will not be able to derive a valid device-profile match from domains alone.

By default, this module assumes your Cloudflare account already has WARP authentication identity enabled with a valid WARP auth session duration. If you want Terraform to configure that account-level setting for you, explicitly add:

```bash
-var='cloudflare_manage_zero_trust_organization=true'
```

If you previously enabled `cloudflare_zero_trust_organization` in this module and want to stop managing it cleanly, first set `cloudflare_manage_zero_trust_organization=false`, then remove it from local Terraform state:

```bash
terraform state rm 'cloudflare_zero_trust_organization.current[0]'
```

### 2. Deploy
```bash
export CLOUDFLARE_API_TOKEN=<CLOUDFLARE_API_TOKEN>

terraform apply -var-file=dev.tfvars
```

Populate `dev.tfvars` with your local values. This repo ignores that file so you can keep machine-specific settings there, including your SSH public key, current `ssh_allowed_cidr`, Cloudflare account/tunnel IDs, and team selectors.

Terraform fails fast on ambiguous Cloudflare combinations:
- `cloudflare_account_id` and `cloudflare_tunnel_id` must be set together.
- Domain-only selectors are not enough to manage the team WARP profile unless you also set `cloudflare_warp_profile_match`.

If you provide `TF_VAR_cloudflare_tunnel_token` at apply time, bootstrap will install and start `cloudflared` automatically on first boot. If you leave that variable unset, Terraform will still provision the VM and Cloudflare resources, but you must install and configure `cloudflared` on the VM yourself.

### Terraform State Backend

This repo is already configured to use the Terraform `s3` backend via `backend.tf`. The Scaleway Object Storage bucket must exist first, so create it in the separate sibling project under `../tfstate-bootstrap`:

```bash
cd ../tfstate-bootstrap
terraform init
terraform apply -var='bucket_name=<globally-unique-bucket-name>'
cd ../simple-vm
```

Then verify `scaleway.s3.tfbackend` points at that bucket and region, export your Scaleway credentials using the AWS-compatible variable names expected by Terraform's `s3` backend, and initialize or migrate the state:

```bash
export AWS_ACCESS_KEY_ID="$SCW_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$SCW_SECRET_KEY"
terraform init -reconfigure -backend-config=scaleway.s3.tfbackend
```

Keep `use_path_style = true` in the backend config for Scaleway Object Storage. Without it, Terraform may try bucket-style DNS names that do not resolve for this backend setup.

Scaleway Object Storage is S3-compatible, but Scaleway documents that Terraform state stored through an AWS S3-compatible bucket does not currently have a supported locking mechanism. Treat this backend as single-writer and avoid concurrent `terraform apply` runs.

If you are moving existing local state into the remote backend, use:

```bash
terraform init -migrate-state -reconfigure -backend-config=scaleway.s3.tfbackend
```

If you do not want Terraform to manage Cloudflare resources, leave the Cloudflare Terraform inputs unset and configure the private route and private apps manually in Cloudflare. You can still install and configure `cloudflared` on the VM separately if you need tunnel-based routing.

To override the automatically-derived team-specific WARP profile, add variables like:

```bash
-var='cloudflare_warp_profile_match=identity.groups.id == "<ACCESS_GROUP_ID>"' \
-var='cloudflare_warp_profile_include_extra_hosts=["<team>.cloudflareaccess.com","<idp-hostname>"]'
```

### 3. Onboard the Team with WARP

Each team member should:
- Install the Cloudflare One client.
- Enroll their device into your Zero Trust organization through the WARP enrollment application Terraform created, or through your existing dashboard flow if you kept enrollment outside Terraform.
- Connect WARP and confirm the route returned by `terraform output warp_private_route_cidr` is active.
- Use the private apps only after their identity matches one of the Terraform-managed selectors.
- Receive the restricted team kubeconfig from an admin; team members do not need SSH access to the VM.

To print the exact local steps from the current Terraform state, run:

```bash
./scripts/onboarding.sh
```

If the VM already existed before this RBAC automation was added, install the restricted team access on the current VM with:

```bash
./scripts/setup-team-access.sh
```

The generated team kubeconfig is backed by a dedicated service account that is bound to the built-in `admin` ClusterRole in non-system namespaces. That means:
- team members can list namespaces
- team members can create, update, and delete namespaced resources in application namespaces
- team members do not get access in `kube-system`, `kube-public`, or `kube-node-lease`
- they do not get Kubernetes node API access
- they do get cluster-wide read/write access to `CustomResourceDefinition` objects
- if you add namespaces later, rerun `./scripts/setup-team-access.sh`

### 4. Connect to Kubernetes via Cloudflare WARP

Admins can still use the full-access kubeconfig if needed. Once the bootstrap finishes (check `/var/log/platform-mesh-bootstrap.log` on the VM), use:

```bash
# Example command from 'terraform output admin_warp_kubeconfig_command'
scp naira@<PUBLIC_IP>:/home/naira/.kube/config ./kind.kubeconfig
perl -0pi -e 's#server: https://127.0.0.1:6443#server: https://<PRIVATE_IP>:6443#g' ./kind.kubeconfig
export KUBECONFIG=$(pwd)/kind.kubeconfig

# Test direct, secure access (No warnings!)
kubectl get nodes
```

### 5. Access the Portal

The default portal workflow is local port-forwarding plus the VM-generated root CA:
- Retrieve the restricted team kubeconfig and root CA instructions from `./scripts/onboarding.sh`.
- Start a local forward with `kubectl --kubeconfig ./platform-mesh-team.kubeconfig -n default port-forward svc/traefik 8443:8443`.
- Open `https://portal.localhost:8443`.
- Import the PEM from the `scp` command printed by `./scripts/onboarding.sh` into your workstation trust store if your browser does not trust the portal certificate yet.

#### Why `portal.localhost` Requires Port-Forwarding

The default portal hostname is `portal.localhost`. On macOS, adding a DNS or `/etc/hosts` entry does not make `portal.localhost` behave like a normal remote hostname. Names under `localhost` are treated as loopback on the local machine, so `portal.localhost` resolves to your own computer, not the VM.

Because of that, the supported access method is local `kubectl port-forward`:

```bash
kubectl --kubeconfig ./platform-mesh-team.kubeconfig -n default port-forward svc/traefik 8443:8443
```

Then open:

```text
https://portal.localhost:8443
```

This works because your browser connects to port `8443` on your own machine, and `kubectl` forwards that traffic into the cluster's Traefik service.

This means:
- `/etc/hosts` is not needed for `portal.localhost`
- private DNS is not needed for the default setup
- each user accesses the portal through their own local port-forward
- the portal is only reachable while the port-forward session is running

If you choose a custom shared hostname instead, set `platform_mesh_base_domain` to that DNS name and map it through your preferred private DNS path.

## Operational Notes

- **Bootstrap Logs**: Monitor progress with `ssh naira@<PUBLIC_IP> "tail -f /var/log/platform-mesh-bootstrap.log"`.
- **Certificates**: The Kubernetes API certificate is automatically generated to trust the VM's private IP.
- **Public Exposure**: `6443` and `8443` are no longer exposed on the VM public IP; reach them through WARP.
- **Tunnel Token Handling**: If you set `cloudflare_tunnel_token`, the token is rendered into `cloud-init` and stored in Terraform state so bootstrap can install `cloudflared` automatically. Treat your Terraform backend and VM user-data access as sensitive.
- **Existing Enrollment Apps**: `cloudflare_manage_device_enrollment` defaults to `false` because Cloudflare allows only one WARP enrollment app per account.
- **Account-Level WARP Auth**: `cloudflare_manage_zero_trust_organization` defaults to `false` because the Zero Trust organization object is persistent and Terraform warns about destroy semantics. Enable it only if you deliberately want Terraform to manage that account-level setting.
- **Team Helper**: `./scripts/onboarding.sh` prints the live onboarding commands from Terraform outputs, including the local Traefik port-forward command when using `portal.localhost`.
- **Restricted Team Kubeconfig**: Run `./scripts/onboarding.sh` to print the current copy command for secure distribution, and rerun `./scripts/setup-team-access.sh` after namespace changes.
- **Shell Profile**: Sourced from `.bashrc`, providing `k` alias, `kubectl` completion, and `KIND_EXPERIMENTAL_PROVIDER=podman`.
- **Kind Wrapper**: A wrapper at `~/bin/kind` ensures that internal setup scripts do not overwrite our custom TLS settings.
- **Trusting the Portal**: To trust the portal's browser certificate, run `./scripts/onboarding.sh`, copy the printed root CA `scp` command, and add the PEM to your OS keychain.

## Security Warning: Cloudflare Tunnel Token
This repository has been updated to accept the `cloudflare_tunnel_token` as a sensitive Terraform variable. 

To prevent this secret from leaking:
1. **Never** hardcode the token in your `.tfvars` file.
2. Pass it securely via the command line using `TF_VAR_cloudflare_tunnel_token="<your-token>" terraform apply`.
3. Because the token is passed to `cloud-init`, it will be visible in the Scaleway console's "User Data" section for this VM, and it will be stored in your `terraform.tfstate` file. Ensure your Terraform backend (e.g., S3) is heavily restricted and encrypted.
