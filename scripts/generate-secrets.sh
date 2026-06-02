#!/usr/bin/env bash
#
# generate-secrets.sh
# Generates all Docker secrets required by the chat-infra stack.
#
# Usage:
#   chmod +x scripts/generate-secrets.sh
#   ./scripts/generate-secrets.sh
#
# Safety rules:
#   - Never overwrites an existing secret (run with --force to regenerate)
#   - Never commits secrets (verifies .gitignore before writing)
#   - Requires openssl  fails fast if not found
#

set -euo pipefail

#  Colours 
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

#  Helpers 
info()    { echo -e "${CYAN}[info]${RESET}  $*"; }
success() { echo -e "${GREEN}[ok]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[warn]${RESET}  $*"; }
die()     { echo -e "${RED}[error]${RESET} $*" >&2; exit 1; }

#  Resolve script location  works regardless of where you call it from 
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECRETS_DIR="${REPO_ROOT}/secrets"

#  Parse flags 
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

#  Preflight checks 
command -v openssl &>/dev/null || die "openssl is required but not installed."

# Ensure secrets/ is in .gitignore before writing anything
GITIGNORE="${REPO_ROOT}/.gitignore"
if ! grep -qxF "secrets/" "${GITIGNORE}" 2>/dev/null; then
  die ".gitignore does not contain 'secrets/'. Add it before running this script.\n  echo 'secrets/' >> .gitignore"
fi

#  Create secrets directory 
mkdir -p "${SECRETS_DIR}"
# Owner read/write only  no group or other access
chmod 700 "${SECRETS_DIR}"

#  Secret definitions 
# Format: "filename:byte_length:description"
# byte_length is passed to openssl rand -base64  output will be longer due to base64 encoding.
declare -a SECRETS=(
  "postgres_password:32:PostgreSQL superuser password"
  "redis_password:32:Redis AUTH password"
  "jwt_secret:64:JWT signing secret (HS256)  must be at least 32 bytes after decode"
  "nats_password:32:NATS authentication password"
  "grafana_password:32:Grafana admin password"
  "minio_root_password:32:MinIO root password"
)

#  Generate 
echo ""
echo -e "${BOLD}chat-infra secret generation${RESET}"
echo -e "Target directory: ${SECRETS_DIR}"
echo ""

GENERATED=0
SKIPPED=0

for entry in "${SECRETS[@]}"; do
  IFS=':' read -r filename byte_len description <<< "${entry}"
  filepath="${SECRETS_DIR}/${filename}.txt"

  if [[ -f "${filepath}" ]] && [[ "${FORCE}" == false ]]; then
    warn "Skipping ${filename}.txt  already exists (use --force to regenerate)"
    (( SKIPPED++ )) || true
    continue
  fi

  if [[ -f "${filepath}" ]] && [[ "${FORCE}" == true ]]; then
    warn "Regenerating ${filename}.txt  existing sessions will be invalidated"
  fi

  # Generate secret  strip trailing newline/whitespace
  openssl rand -base64 "${byte_len}" | tr -d '\n' > "${filepath}"

  # Owner read-only  prevents accidental modification
  chmod 600 "${filepath}"

  success "Generated ${filename}.txt (${description})"
  (( GENERATED++ )) || true
done

#  Summary 
echo ""
echo -e "${BOLD}Summary${RESET}"
echo -e "  Generated : ${GREEN}${GENERATED}${RESET}"
echo -e "  Skipped   : ${YELLOW}${SKIPPED}${RESET}"
echo ""

if [[ "${GENERATED}" -gt 0 ]]; then
  info "Secrets written to: ${SECRETS_DIR}/"
  info "Permissions set to 600 (owner read-only)"
  info "Directory permissions set to 700 (owner only)"
  echo ""
  echo -e "${YELLOW}Never commit the secrets/ directory.${RESET}"
  echo -e "Verify: ${CYAN}cat .gitignore | grep secrets${RESET}"
fi