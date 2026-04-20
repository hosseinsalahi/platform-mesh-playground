check "cloudflare_route_inputs_complete" {
  assert {
    condition = (
      (var.cloudflare_account_id == null && var.cloudflare_tunnel_id == null) ||
      (var.cloudflare_account_id != null && var.cloudflare_tunnel_id != null)
    )
    error_message = "cloudflare_account_id and cloudflare_tunnel_id must either both be set or both be unset."
  }
}

check "cloudflare_team_warp_profile_inputs_usable" {
  assert {
    condition = !(
      local.cloudflare_zero_trust_enabled &&
      length(local.cloudflare_access_policy_include) > 0 &&
      local.cloudflare_manage_effective_team_warp_profile &&
      local.cloudflare_effective_warp_profile_match == null
    )
    error_message = "Team WARP profile management requires explicit team emails, Access group IDs, or cloudflare_warp_profile_match. Domain-only selectors cannot derive a device-profile match."
  }
}
