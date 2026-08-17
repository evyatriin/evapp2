# EVraahein Production Launch

## Implemented

- Cloud Run backend deployed in `evraahein-prod`, region `asia-south1`.
- Runtime identity uses Secret Manager for Supabase, Maps, and HERE credentials.
- Cloud Run is limited to 1 CPU, 512 MiB, 1-5 instances, and concurrency 10.
- Supabase sessions persist on device and refresh automatically.
- Protected backend requests attach the current Supabase access token.
- User-owned API operations validate the authenticated user.
- Admin news mutations require an authenticated administrator.
- Public point-award and streak-mutation endpoints are removed.
- Paid routing and place APIs require authentication.
- Uploads require authentication and validate type and size.
- SOS and production ads are disabled until their workflows are complete.
- Signup records acceptance of the Terms of Service and Privacy Policy.
- Onboarding no longer forces location or vehicle setup.
- Readiness checks verify required configuration and database connectivity.
- Backend tests, Flutter tests, and static analysis run cleanly.
- Android release builds fail when upload signing is not configured.
- The Android upload key is backed up in Secret Manager.

## Required Before Store Submission

- Rotate the Supabase anon and service-role keys exposed during migration, then
  update Secret Manager and the Flutter release build.
- Confirm the permanent Android application ID. It is currently
  `com.evranger.ev_router_app2`; changing it after Play Console publication
  creates a different app.
- Add a valid Sentry DSN version to the existing `sentry-dsn` secret before
  enabling backend error reporting.
- Restrict the Android Google Maps key by package name and upload certificate
  SHA-256, and restrict the backend Maps/HERE keys to required APIs.
- Complete Play Console data-safety, privacy, content-rating, support, and
  account-deletion declarations.
- Run a closed-track device test for signup, email confirmation, login, route
  planning, chargers, profile editing, password reset, and account deletion.
- Run sustained load tests before raising Cloud Run concurrency or maximum
  instances. Several Supabase calls are synchronous and should be moved to
  thread-backed or async clients before high traffic.
