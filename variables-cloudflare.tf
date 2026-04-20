variable "cloudflare_account_id" {
  description = "Cloudflare account ID for managing the WARP private route and Zero Trust resources."
  type        = string
  default     = null
  nullable    = true
}

variable "cloudflare_tunnel_id" {
  description = "Existing remotely-managed Cloudflare Tunnel UUID used by the VM."
  type        = string
  default     = null
  nullable    = true
}

variable "cloudflare_allowed_idp_ids" {
  description = "Zero Trust identity provider IDs allowed for team login. Leave empty to allow all configured IdPs."
  type        = list(string)
  default     = []
}

variable "cloudflare_team_email_domains" {
  description = "Email domains allowed to enroll devices and reach the private apps, for example ['company.com', 'partner.example']."
  type        = list(string)
  default     = []
}

variable "cloudflare_team_emails" {
  description = "Specific user email addresses allowed to enroll devices and reach the private apps."
  type        = list(string)
  default     = []
}

variable "cloudflare_team_access_group_ids" {
  description = "Existing Cloudflare Access group IDs that should be allowed to enroll devices and reach the private apps."
  type        = list(string)
  default     = []
}

variable "cloudflare_access_policy_session_duration" {
  description = "Session duration applied to the team Access policy and private apps."
  type        = string
  default     = "24h"
}

variable "cloudflare_manage_zero_trust_organization" {
  description = "Whether Terraform should manage the account-level Zero Trust organization settings required for WARP-authenticated private apps. Disabled by default to avoid Terraform lifecycle warnings on this persistent Cloudflare object."
  type        = bool
  default     = false
}

variable "cloudflare_warp_auth_session_duration" {
  description = "Account-level WARP auth session duration required before private Access applications can set allow_authenticate_via_warp."
  type        = string
  default     = "24h"
}

variable "cloudflare_manage_device_enrollment" {
  description = "Whether Terraform should manage the WARP device enrollment application. Default is false because most Zero Trust accounts already have one."
  type        = bool
  default     = false
}

variable "cloudflare_manage_private_app_access" {
  description = "Whether Terraform should manage the private Access applications for the Kubernetes API and portal."
  type        = bool
  default     = true
}

variable "cloudflare_manage_team_warp_profile" {
  description = "Whether Terraform should manage a team-specific WARP device profile that routes the VM private IP through WARP."
  type        = bool
  default     = true
}

variable "cloudflare_warp_profile_match" {
  description = "Optional WARP device profile match expression override. Leave unset to derive the profile match from the team email and group selectors."
  type        = string
  default     = null
  nullable    = true
}

variable "cloudflare_warp_profile_name" {
  description = "Name of the optional team-specific WARP custom profile."
  type        = string
  default     = "Platform Mesh team"
}

variable "cloudflare_warp_profile_precedence" {
  description = "Precedence of the optional team-specific WARP custom profile. Lower numbers win."
  type        = number
  default     = 100
}

variable "cloudflare_warp_profile_include_extra_cidrs" {
  description = "Extra CIDRs to include in the optional team-specific WARP custom profile."
  type        = list(string)
  default     = []
}

variable "cloudflare_warp_profile_include_extra_hosts" {
  description = "Extra hostnames to include in the optional team-specific WARP custom profile. Include your team domain and IdP hostnames if you use Split Tunnel Include mode."
  type        = list(string)
  default     = []
}
