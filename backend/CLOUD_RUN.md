# Cloud Run Deployment

This backend is ready to run on Google Cloud Run as a containerized FastAPI service.

## Required environment variables

- `SUPABASE_URL`
- `SUPABASE_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `GOOGLE_MAPS_API_KEY`
- `HERE_API_KEY`

Optional:

- `ALLOWED_ORIGINS`
- `APP_ENV=production`
- `OPENCHARGEMAP_API_KEY`

## One-time setup

```bash
gcloud config set project YOUR_PROJECT_ID
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com
```

## Deploy from source

```bash
cd /Users/kk/apps/ev_router_app2
gcloud run deploy ev-ranger-backend \
  --source backend \
  --region asia-south1 \
  --platform managed \
  --allow-unauthenticated \
  --port 8080 \
  --memory 512Mi \
  --cpu 1 \
  --min-instances 0 \
  --max-instances 3 \
  --set-env-vars APP_ENV=production,ALLOWED_ORIGINS=* \
  --set-env-vars SUPABASE_URL=YOUR_SUPABASE_URL,SUPABASE_KEY=YOUR_SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY=YOUR_SUPABASE_SERVICE_ROLE_KEY,GOOGLE_MAPS_API_KEY=YOUR_GOOGLE_MAPS_API_KEY,HERE_API_KEY=YOUR_HERE_API_KEY,OPENCHARGEMAP_API_KEY=YOUR_OPTIONAL_OPENCHARGEMAP_KEY
```

## Health checks

- `GET /health`
- `GET /ready`

## App rebuild

Rebuild the Flutter app with:

```bash
flutter build apk --release --split-per-abi \
  --dart-define=BACKEND_URL=https://YOUR_CLOUD_RUN_URL \
  --dart-define=SUPABASE_URL=https://YOUR_SUPABASE_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
```
