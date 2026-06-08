#!/usr/bin/env bash
# generate-secrets.sh
# Generates all Docker secrets required by the pree-it-infra stack.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[info]${RESET}  $*"; }
success() { echo -e "${GREEN}[ok]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[warn]${RESET}  $*"; }
die()     { echo -e "${RED}[error]${RESET} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECRETS_DIR="${REPO_ROOT}/secrets"

FORCE=false
for arg in "$@"; do
  case "$arg" in
    --force|-f) FORCE=true ;;
    --help|-h)
      echo "Usage: $0 [--force]"
      echo ""
      echo "  --force   Regenerate all secrets even if they already exist."
      echo "            WARNING: rotating secrets invalidates all active sessions."
      exit 0
      ;;
    *) die "Unknown argument: $arg. Use --help for usage." ;;
  esac
done

command -v openssl &>/dev/null || die "openssl is required but not installed."

GITIGNORE="${REPO_ROOT}/.gitignore"
if ! grep -qxF "secrets/" "${GITIGNORE}" 2>/dev/null; then
  die ".gitignore does not contain 'secrets/'. Add it before running this script.\n  echo 'secrets/' >> .gitignore"
fi

mkdir -p "${SECRETS_DIR}"
chmod 700 "${SECRETS_DIR}"

declare -a SECRETS=(
  "postgres_password:PostgreSQL superuser password:base64:32"
  "redis_password:Redis AUTH password:base64:32"
  "jwt_secret:JWT signing secret — min 32 bytes after decode:base64:64"
  "nats_password:NATS authentication password:base64:32"
  "grafana_password:Grafana admin password:base64:32"
  "garage_rpc_secret:Garage cluster RPC secret — must be 64 hex chars:hex:32"
  "user_db_password:User service PostgreSQL password:base64:32"
  "chat_db_password:Chat service PostgreSQL password:base64:32"
)

echo ""
echo -e "${BOLD}pree-it-infra secret generation${RESET}"
echo -e "Target directory: ${SECRETS_DIR}"
echo ""

GENERATED=0
SKIPPED=0

for entry in "${SECRETS[@]}"; do
  IFS=':' read -r filename description encoding byte_len <<< "${entry}"
  filepath="${SECRETS_DIR}/${filename}.txt"

  if [[ -f "${filepath}" ]] && [[ "${FORCE}" == false ]]; then
    warn "Skipping ${filename}.txt — already exists (use --force to regenerate)"
    (( SKIPPED++ )) || true
    continue
  fi

  if [[ "${encoding}" == "hex" ]]; then
    openssl rand -hex "${byte_len}" | tr -d '\n' > "${filepath}"
  else
    openssl rand -base64 "${byte_len}" | tr -d '\n' > "${filepath}"
  fi

  # Default: owner read-only
  chmod 600 "${filepath}"
  success "Generated ${filename}.txt (${description})"
  (( GENERATED++ )) || true
done

# Per-service permission requirements
#
# Docker Compose mounts file-based secrets as root:root 0400 by default.
# Services running as non-root users cannot read 0400 secrets owned by root.
#
# Grafana runs as uid 472 (hardcoded in the official image).
# Setting grafana_password.txt to 0444 allows uid 472 to read it while
# keeping it unwritable by anyone. This is acceptable because the file
# contains only a password that is also stored in the Grafana database —
# world-readability on the host is the same risk as any other config file.
#
if [[ -f "${SECRETS_DIR}/grafana_password.txt" ]]; then
  chmod 0444 "${SECRETS_DIR}/grafana_password.txt"
  info "grafana_password.txt → 0444 (Grafana uid 472 requires world-read)"
fi

# auth and gateway run as uid 10001 (app user in alpine production image)
# secrets must be world-readable for the non-root process to read them
for secret in postgres_password redis_password jwt_secret nats_password user_db_password chat_db_password; do
  if [[ -f "${SECRETS_DIR}/${secret}.txt" ]]; then
    chmod 0444 "${SECRETS_DIR}/${secret}.txt"
    info "${secret}.txt → 0444 (app uid 10001 requires world-read)"
  fi
done

echo ""
echo -e "${BOLD}Summary${RESET}"
echo -e "  Generated : ${GREEN}${GENERATED}${RESET}"
echo -e "  Skipped   : ${YELLOW}${SKIPPED}${RESET}"
echo ""

if [[ "${GENERATED}" -gt 0 ]]; then
  info "Secrets written to: ${SECRETS_DIR}/"
  info "Directory permissions: 700 (owner only)"
  echo ""
  echo -e "${YELLOW}Never commit the secrets/ directory.${RESET}"
  echo -e "Verify: ${CYAN}grep secrets .gitignore${RESET}"
fi