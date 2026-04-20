resource "cloudflare_zero_trust_tunnel_cloudflared_route" "vm" {
  count      = local.cloudflare_route_enabled ? 1 : 0
  account_id = var.cloudflare_account_id
  network    = local.warp_route_cidr
  tunnel_id  = var.cloudflare_tunnel_id
  comment    = "Platform Mesh VM private IP"
}
