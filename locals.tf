locals {
  cloudflare_route_enabled = var.cloudflare_account_id != null && var.cloudflare_tunnel_id != null
  private_ip               = one([for ip in scaleway_instance_server.vm.private_ips : ip.address if can(regex("^[0-9.]+$", ip.address))])
  warp_route_cidr          = format("%s/32", local.private_ip)

  cloudflare_zero_trust_enabled                 = var.cloudflare_account_id != null
  cloudflare_organization_enabled               = local.cloudflare_zero_trust_enabled && var.cloudflare_manage_zero_trust_organization
  cloudflare_allowed_idps                       = length(var.cloudflare_allowed_idp_ids) > 0 ? var.cloudflare_allowed_idp_ids : null
  cloudflare_manage_effective_team_warp_profile = var.cloudflare_manage_team_warp_profile
  cloudflare_team_domains                       = distinct(var.cloudflare_team_email_domains)
  cloudflare_effective_team_emails              = distinct(var.cloudflare_team_emails)
  cloudflare_effective_team_access_group_ids    = distinct(var.cloudflare_team_access_group_ids)
  cloudflare_access_policy_include = concat(
    [for domain in local.cloudflare_team_domains : {
      email_domain = {
        domain = domain
      }
    }],
    [for email in local.cloudflare_effective_team_emails : {
      email = {
        email = email
      }
    }],
    [for group_id in local.cloudflare_effective_team_access_group_ids : {
      group = {
        id = group_id
      }
    }],
  )
  cloudflare_team_access_enabled = local.cloudflare_zero_trust_enabled && length(local.cloudflare_access_policy_include) > 0
  cloudflare_default_warp_profile_match_clauses = compact(concat(
    length(local.cloudflare_effective_team_access_group_ids) > 0 ? [
      format(
        "identity.groups.id in {%s}",
        join(" ", [for group_id in local.cloudflare_effective_team_access_group_ids : format("%q", group_id)]),
      ),
    ] : [],
    length(local.cloudflare_effective_team_emails) > 0 ? [
      format(
        "identity.email in {%s}",
        join(" ", [for email in local.cloudflare_effective_team_emails : format("%q", email)]),
      ),
    ] : [],
  ))
  cloudflare_effective_warp_profile_match = var.cloudflare_warp_profile_match != null ? var.cloudflare_warp_profile_match : (
    length(local.cloudflare_default_warp_profile_match_clauses) > 0 ? join(" or ", local.cloudflare_default_warp_profile_match_clauses) : null
  )
  cloudflare_device_profile_enabled = (
    local.cloudflare_team_access_enabled &&
    local.cloudflare_manage_effective_team_warp_profile &&
    local.cloudflare_effective_warp_profile_match != null
  )
  cloudflare_private_app_access_enabled = local.cloudflare_team_access_enabled && var.cloudflare_manage_private_app_access
  cloudflare_private_access_apps = {
    kubernetes_api = {
      name = "Platform Mesh Kubernetes API"
      port = "6443"
    }
    portal = {
      name = "Platform Mesh portal"
      port = "8443"
    }
  }
  cloudflare_warp_profile_include = concat(
    local.cloudflare_zero_trust_enabled ? [{
      host        = data.cloudflare_zero_trust_organization.team[0].auth_domain
      description = "Cloudflare Zero Trust team domain"
    }] : [],
    [{
      address     = local.warp_route_cidr
      description = "Platform Mesh VM private route"
    }],
    [for cidr in var.cloudflare_warp_profile_include_extra_cidrs : {
      address     = cidr
      description = "Additional Platform Mesh route"
    }],
    [for host in var.cloudflare_warp_profile_include_extra_hosts : {
      host        = host
      description = "Supporting hostname required with Platform Mesh"
    }],
  )
}
