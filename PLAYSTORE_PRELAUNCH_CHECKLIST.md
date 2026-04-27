# Play Store Pre-Launch Checklist

## Release blockers

- [ ] Configure Android release signing with a real upload keystore.
- [ ] Add `android/key.properties` from `android/key.properties.example`.
- [ ] Set `MAPS_API_KEY` in `android/local.properties` or another local Gradle property source.
- [ ] Set `ADMOB_APP_ID` in `android/local.properties`.
- [ ] Build release with real banner IDs:
  `flutter build appbundle --release --dart-define=ADMOB_BANNER_ANDROID=... --dart-define=ADMOB_BANNER_IOS=...`
- [ ] Replace the mock account deletion flow with real backend deletion.
- [ ] Replace the mock phone OTP verification flow.
- [ ] Remove or finish any user-facing mock/demo features such as SOS fallback IDs and mock news.

## Android checks

- [ ] Confirm app name, icon, and package ID are final.
- [ ] Verify `versionName` and `versionCode` for the release.
- [ ] Run `flutter analyze`.
- [ ] Run widget and integration tests.
- [ ] Build a signed `.aab` and install a release build on a physical device.
- [ ] Validate ads stay off in release if production IDs are missing.
- [ ] Verify Maps and location flows work with the production API key.
- [ ] Check runtime permission flows for location, camera, and gallery access.

## Play Console checks

- [ ] Upload a privacy policy URL that matches actual data handling.
- [ ] Complete the Data safety form for account data, precise/coarse location, photos, diagnostics, and ads data sharing if applicable.
- [ ] Add an account deletion URL and ensure in-app deletion is available.
- [ ] Complete content rating, app access, and ads declarations.
- [ ] Prepare screenshots, feature graphic, app description, and support contact.
- [ ] Roll out to internal testing before production.

## Backend and policy checks

- [ ] Verify Supabase auth, storage, and backend APIs work in production.
- [ ] Confirm retention/deletion behavior for user accounts, uploaded photos, and check-in content.
- [ ] Replace placeholder legal copy with final Terms and Privacy Policy text.
- [ ] Verify support email and website are active.
