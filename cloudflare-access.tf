data "cloudflare_zero_trust_organization" "team" {
  count      = local.cloudflare_zero_trust_enabled ? 1 : 0
  account_id = var.cloudflare_account_id
}

resource "cloudflare_zero_trust_organization" "current" {
  count      = local.cloudflare_organization_enabled ? 1 : 0
  account_id = var.cloudflare_account_id

  auth_domain                = data.cloudflare_zero_trust_organization.team[0].auth_domain
  warp_auth_session_duration = var.cloudflare_warp_auth_session_duration
}

resource "cloudflare_zero_trust_access_policy" "team" {
  count      = local.cloudflare_team_access_enabled ? 1 : 0
  account_id = var.cloudflare_account_id

  name             = "Platform Mesh team"
  decision         = "allow"
  include          = local.cloudflare_access_policy_include
  session_duration = var.cloudflare_access_policy_session_duration
}

resource "cloudflare_zero_trust_access_application" "device_enrollment" {
  count      = local.cloudflare_team_access_enabled && var.cloudflare_manage_device_enrollment ? 1 : 0
  account_id = var.cloudflare_account_id

  name         = "Platform Mesh team device enrollment"
  type         = "warp"
  allowed_idps = local.cloudflare_allowed_idps
  policies = [{
    id         = cloudflare_zero_trust_access_policy.team[0].id
    precedence = 1
  }]
  session_duration = var.cloudflare_access_policy_session_duration
}

resource "cloudflare_zero_trust_access_application" "private_apps" {
  for_each = local.cloudflare_private_app_access_enabled ? local.cloudflare_private_access_apps : {}

  account_id = var.cloudflare_account_id

  name                        = each.value.name
  type                        = "self_hosted"
  app_launcher_visible        = false
  allow_authenticate_via_warp = true
  allowed_idps                = local.cloudflare_allowed_idps
  destinations = [{
    type        = "private"
    cidr        = local.warp_route_cidr
    l4_protocol = "tcp"
    port_range  = each.value.port
  }]
  policies = [{
    id         = cloudflare_zero_trust_access_policy.team[0].id
    precedence = 1
  }]
  session_duration = var.cloudflare_access_policy_session_duration

  depends_on = [cloudflare_zero_trust_organization.current]
}

resource "cloudflare_zero_trust_device_custom_profile" "team" {
  count      = local.cloudflare_device_profile_enabled ? 1 : 0
  account_id = var.cloudflare_account_id

  name              = var.cloudflare_warp_profile_name
  description       = "Routes Platform Mesh private traffic through WARP for team devices."
  enabled           = true
  precedence        = var.cloudflare_warp_profile_precedence
  match             = local.cloudflare_effective_warp_profile_match
  allow_mode_switch = false
  switch_locked     = false
  service_mode_v2 = {
    mode = "warp"
  }
  include = local.cloudflare_warp_profile_include
}
