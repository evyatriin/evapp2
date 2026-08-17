# EVraahein Cloud Run Deployment

The production backend runs as `evraahein-backend` in the `evraahein-prod`
Google Cloud project and `asia-south1` region.

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

## Runtime secrets

Production credentials are stored in Google Secret Manager and exposed only to
`evraahein-backend-runtime@evraahein-prod.iam.gserviceaccount.com`.

GitHub Actions authenticates through the `github-actions/github` workload
identity provider. Do not add a service-account JSON key to repository secrets.

## Health checks

- `GET /health`
- `GET /ready`

## App rebuild

Rebuild the Flutter app with:

```bash
flutter build apk --release --split-per-abi \
  --dart-define=BACKEND_URL=https://evraahein-backend-187759131948.asia-south1.run.app \
  --dart-define=SUPABASE_URL=https://YOUR_SUPABASE_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
```
