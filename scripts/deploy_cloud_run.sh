#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="${ROOT_DIR}/backend"
ENV_FILE="${BACKEND_ENV_FILE:-${BACKEND_DIR}/.env}"
SERVICE_NAME="${SERVICE_NAME:-ev-ranger-backend}"
REGION="${REGION:-asia-south1}"
MEMORY="${MEMORY:-512Mi}"
CPU="${CPU:-1}"
MIN_INSTANCES="${MIN_INSTANCES:-0}"
MAX_INSTANCES="${MAX_INSTANCES:-3}"
ALLOWED_ORIGINS="${ALLOWED_ORIGINS:-*}"

clean_env() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  if [[ "${#value}" -ge 2 ]]; then
    if [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
      value="${value:1:${#value}-2}"
    fi
  fi
  printf '%s' "${value}"
}

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing backend env file: ${ENV_FILE}" >&2
  exit 1
fi

set -a
source "${ENV_FILE}"
set +a

required_vars=(
  SUPABASE_URL
  SUPABASE_KEY
  GOOGLE_MAPS_API_KEY
  HERE_API_KEY
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "Missing required env var in ${ENV_FILE}: ${var_name}" >&2
    exit 1
  fi
done

env_vars=(
  "APP_ENV=production"
  "ALLOWED_ORIGINS=$(clean_env "${ALLOWED_ORIGINS}")"
  "FEATURE_SOS_ENABLED=$(clean_env "${FEATURE_SOS_ENABLED:-true}")"
  "SUPABASE_URL=$(clean_env "${SUPABASE_URL}")"
  "SUPABASE_KEY=$(clean_env "${SUPABASE_KEY}")"
  "GOOGLE_MAPS_API_KEY=$(clean_env "${GOOGLE_MAPS_API_KEY}")"
  "HERE_API_KEY=$(clean_env "${HERE_API_KEY}")"
)

if [[ -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  env_vars+=("SUPABASE_SERVICE_ROLE_KEY=$(clean_env "${SUPABASE_SERVICE_ROLE_KEY}")")
fi

cd "${ROOT_DIR}"

gcloud run deploy "${SERVICE_NAME}" \
  --source backend \
  --region "${REGION}" \
  --platform managed \
  --allow-unauthenticated \
  --port 8080 \
  --memory "${MEMORY}" \
  --cpu "${CPU}" \
  --min-instances "${MIN_INSTANCES}" \
  --max-instances "${MAX_INSTANCES}" \
  --set-env-vars "$(IFS=,; echo "${env_vars[*]}")"
