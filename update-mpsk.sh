#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# ClearPass MPSK Updater für Radius:Aruba / Aruba-MPSK-Passphrase
# ============================================================================

CLEARPASS_API_ROOT="https://clearpass-fqdn-or-ip/api"
CLEARPASS_CLIENT_ID="Endpoint-MPSK-Update"
CLEARPASS_CLIENT_SECRET=""
LOG_DIR="logs"
LOG_FILE="${LOG_DIR}/update-mpsk-$(date +%Y).log"

# ============================================================================

usage() {
  cat >&2 <<EOF
Usage: $0 <enforcement-profile-name> <new-mpsk>

Beispiel:
  $0 "Name-der-Rolle" "neuer-psk-wert"

Das Script holt ein Enforcement Profile, ersetzt das Attribut
type="Radius:Aruba" name="Aruba-MPSK-Passphrase" und schreibt 
das Enforcement Profil mit dem neuen PSK zurück
EOF
  exit 1
}

[ $# -ne 2 ] && usage

PROFILE_NAME="$1"
NEW_MPSK="$2"
API_ROOT="${CLEARPASS_API_ROOT%/}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command '$1' not found" >&2
    exit 1
  fi
}

require_command curl
require_command jq

mkdir -p "$LOG_DIR"

log_msg() {
  local level="$1"
  shift
  local message="$*"
  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  local line="${timestamp} ${level}: ${message}"
  echo "$line" >>"$LOG_FILE"
  echo "$line" >&2
}

log_info() { log_msg "INFO" "$*"; }
log_error() { log_msg "ERROR" "$*"; }

# ============================================================================
# Token holen
# ============================================================================

log_info "requesting bearer token..."

TOKEN_RESPONSE=$(
  curl -sS --insecure \
    -H 'Content-Type: application/json' \
    -X POST \
    "${API_ROOT}/oauth" \
    -d "{\"grant_type\":\"client_credentials\",\"client_id\":\"${CLEARPASS_CLIENT_ID}\",\"client_secret\":\"${CLEARPASS_CLIENT_SECRET}\"}" \
    -w "\n%{http_code}"
)

TOKEN_HTTP_CODE="${TOKEN_RESPONSE##*$'\n'}"
TOKEN_BODY="${TOKEN_RESPONSE%$'\n'*}"

if [ "$TOKEN_HTTP_CODE" != "200" ]; then
  log_error "token request failed with HTTP $TOKEN_HTTP_CODE"
  log_error "token response: $TOKEN_BODY"
  exit 3
fi

TOKEN=$(jq -r '.access_token // empty' <<<"$TOKEN_BODY")

if [ -z "$TOKEN" ]; then
  log_error "failed to get access token"
  exit 3
fi

# ============================================================================
# Profil laden
# ============================================================================

log_info "fetching enforcement profile '$PROFILE_NAME'..."

ENCODED_NAME=$(printf '%s' "$PROFILE_NAME" | jq -sRr @uri)

PROFILE_RESPONSE=$(
  curl -sS --insecure \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Accept: application/vnd.enforcement-profile.v1+json' \
    "${API_ROOT}/enforcement-profile/name/${ENCODED_NAME}" \
    -w "\n%{http_code}"
)

PROFILE_HTTP_CODE="${PROFILE_RESPONSE##*$'\n'}"
PROFILE="${PROFILE_RESPONSE%$'\n'*}"

if [ "$PROFILE_HTTP_CODE" != "200" ]; then
  log_error "failed to fetch profile, HTTP $PROFILE_HTTP_CODE"
  log_error "profile response: $PROFILE"
  exit 4
fi

# ============================================================================
# Prüfe, ob MPSK-Attribut existiert
# ============================================================================

HAS_MPSK=$(
  jq '[.attributes[]? | select(
    .type == "Radius:Aruba" and
    .name == "Aruba-MPSK-Passphrase"
  )] | length' <<<"$PROFILE"
)

if [ "$HAS_MPSK" -eq 0 ]; then
  log_error "enforcement profile does not contain Aruba-MPSK-Passphrase attribute"
  exit 5
fi

log_info "found Aruba-MPSK-Passphrase, updating..."
log_info "setting Aruba-MPSK-Passphrase to: $NEW_MPSK"

# ============================================================================
# Payload bauen
# ============================================================================

PATCH_PAYLOAD=$(
  jq --arg new_mpsk "$NEW_MPSK" '
    .attributes |= map(
      if .type == "Radius:Aruba" and .name == "Aruba-MPSK-Passphrase" then
        .value = $new_mpsk
      else
        .
      end
    ) |
    {name, type, action, attributes}
  ' <<<"$PROFILE"
)

# ============================================================================
# Profil akutalisieren
# ============================================================================

RESULT_RESPONSE=$(
  curl -sS --insecure \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $TOKEN" \
    -X PATCH \
    "${API_ROOT}/enforcement-profile/name/${ENCODED_NAME}" \
    -d "$PATCH_PAYLOAD" \
    -w "\n%{http_code}"
)

RESULT_HTTP_CODE="${RESULT_RESPONSE##*$'\n'}"
RESULT="${RESULT_RESPONSE%$'\n'*}"

if [ "$RESULT_HTTP_CODE" -lt 200 ] || [ "$RESULT_HTTP_CODE" -ge 300 ]; then
  log_error "profile update failed, HTTP $RESULT_HTTP_CODE"
  log_error "patch response: $RESULT"
  exit 6
fi

if echo "$RESULT" | jq -e '.id' >/dev/null 2>&1; then
  log_info "enforcement profile '$PROFILE_NAME' updated successfully."
  exit 0
else
  log_error "failed to update profile: $RESULT"
  exit 6
fi