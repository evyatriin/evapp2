#!/usr/bin/env bash
#
# Create (or update) a Cloud Scheduler job that pings the backend /health every
# 5 minutes so Cloud Run keeps a warm instance even if min-instances is 0.
# Idempotent: creates the job, or updates it if it already exists.
#
# Requires the Cloud Scheduler API enabled on the project.

set -euo pipefail

PROJECT="${PROJECT:-sensous-prod-1778268660}"
REGION="${REGION:-us-central1}"
JOB_NAME="${JOB_NAME:-ev-router-backend-keepwarm}"
SERVICE_URL="${SERVICE_URL:-https://ev-router-backend-41342649973.us-central1.run.app}"
SCHEDULE="${SCHEDULE:-*/5 * * * *}"

common_args=(
  --project "${PROJECT}"
  --location "${REGION}"
  --schedule "${SCHEDULE}"
  --uri "${SERVICE_URL}/health"
  --http-method GET
  --attempt-deadline 30s
)

if gcloud scheduler jobs describe "${JOB_NAME}" --project "${PROJECT}" --location "${REGION}" >/dev/null 2>&1; then
  echo "Updating existing keep-warm job ${JOB_NAME}..."
  gcloud scheduler jobs update http "${JOB_NAME}" "${common_args[@]}"
else
  echo "Creating keep-warm job ${JOB_NAME}..."
  gcloud scheduler jobs create http "${JOB_NAME}" "${common_args[@]}"
fi

echo "Done. Verify: gcloud scheduler jobs describe ${JOB_NAME} --project ${PROJECT} --location ${REGION}"
