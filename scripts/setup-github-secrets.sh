#!/usr/bin/env bash
# Populates GitHub Actions secrets and repository variables for Terraform CI.
#
# Prerequisites:
#   - gh CLI authenticated (e.g. gh auth login)
#   - Run from a git clone of this repository (uses default remote)
#
# Usage:
#   export SCW_ACCESS_KEY=...
#   export SCW_SECRET_KEY=...
#   export TF_STATE_ACCESS_KEY=... # optional; defaults to SCW_ACCESS_KEY
#   export TF_STATE_SECRET_KEY=... # optional; defaults to SCW_SECRET_KEY
#   ... (see README CI section)
#   ./scripts/setup-github-secrets.sh
#
# Values are read from your environment and never printed by this script.

set -euo pipefail

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: '$1' not found in PATH" >&2
    exit 1
  fi
}

require_nonempty() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "error: required environment variable ${name} is not set" >&2
    exit 1
  fi
}

set_repo_secret() {
  local name="$1"
  local value="$2"
  printf '%s' "${value}" | gh secret set "${name}"
}

set_repo_var() {
  local name="$1"
  local value="$2"
  gh variable set "${name}" --body "${value}"
}

main() {
  require_cmd gh

  require_nonempty SCW_ACCESS_KEY
  require_nonempty SCW_SECRET_KEY
  require_nonempty SCW_DEFAULT_PROJECT_ID
  require_nonempty CLOUDFLARE_API_TOKEN

  require_nonempty TF_VAR_SSH_PUBLIC_KEY
  require_nonempty TF_VAR_SSH_ALLOWED_CIDR

  require_nonempty TF_STATE_BUCKET
  require_nonempty TF_STATE_KEY
  require_nonempty TF_STATE_REGION
  require_nonempty TF_STATE_S3_ENDPOINT

  set_repo_secret SCW_ACCESS_KEY "${SCW_ACCESS_KEY}"
  set_repo_secret SCW_SECRET_KEY "${SCW_SECRET_KEY}"
  set_repo_secret SCW_DEFAULT_PROJECT_ID "${SCW_DEFAULT_PROJECT_ID}"
  set_repo_secret CLOUDFLARE_API_TOKEN "${CLOUDFLARE_API_TOKEN}"
  set_repo_secret TF_STATE_ACCESS_KEY "${TF_STATE_ACCESS_KEY:-${SCW_ACCESS_KEY}}"
  set_repo_secret TF_STATE_SECRET_KEY "${TF_STATE_SECRET_KEY:-${SCW_SECRET_KEY}}"

  set_repo_secret TF_VAR_SSH_PUBLIC_KEY "${TF_VAR_SSH_PUBLIC_KEY}"
  set_repo_secret TF_VAR_SSH_ALLOWED_CIDR "${TF_VAR_SSH_ALLOWED_CIDR}"

  if [ -n "${TF_VAR_CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
    set_repo_secret TF_VAR_CLOUDFLARE_TUNNEL_TOKEN "${TF_VAR_CLOUDFLARE_TUNNEL_TOKEN}"
  fi

  if [ -n "${TF_VAR_CLOUDFLARE_ACCOUNT_ID:-}" ]; then
    set_repo_secret TF_VAR_CLOUDFLARE_ACCOUNT_ID "${TF_VAR_CLOUDFLARE_ACCOUNT_ID}"
  fi

  if [ -n "${TF_VAR_CLOUDFLARE_TUNNEL_ID:-}" ]; then
    set_repo_secret TF_VAR_CLOUDFLARE_TUNNEL_ID "${TF_VAR_CLOUDFLARE_TUNNEL_ID}"
  fi

  # Terraform list inputs: JSON arrays, for example ["a.com"] and ["user@example.com"]
  if [ -n "${TF_VAR_CLOUDFLARE_TEAM_EMAIL_DOMAINS:-}" ]; then
    set_repo_secret TF_VAR_CLOUDFLARE_TEAM_EMAIL_DOMAINS "${TF_VAR_CLOUDFLARE_TEAM_EMAIL_DOMAINS}"
  fi
  if [ -n "${TF_VAR_CLOUDFLARE_TEAM_EMAILS:-}" ]; then
    set_repo_secret TF_VAR_CLOUDFLARE_TEAM_EMAILS "${TF_VAR_CLOUDFLARE_TEAM_EMAILS}"
  fi

  set_repo_var TF_STATE_BUCKET "${TF_STATE_BUCKET}"
  set_repo_var TF_STATE_KEY "${TF_STATE_KEY}"
  set_repo_var TF_STATE_REGION "${TF_STATE_REGION}"
  set_repo_var TF_STATE_S3_ENDPOINT "${TF_STATE_S3_ENDPOINT}"

  echo "Done. Verified with: gh secret list && gh variable list"
}

main "$@"
