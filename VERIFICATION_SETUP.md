# Double-Verification for Community Help — Setup & Go-Live

Community help features require users to be **double-verified**: a confirmed
email **and** a verified phone. Enforced both in the app (friendly gate) and on
the backend (tamper-proof).

## Gated actions
| Action | App gate | Backend enforcement |
|---|---|---|
| Send an SOS alert | ✅ `sos_screen` | ✅ `POST /api/sos/alert` |
| Request community charging | ✅ `home_screen` charge sheet | ✅ `POST /api/chargers/request` |
| Host / offer a charger | ✅ `community_charging_screen` | ✅ `POST /api/chargers/host` |
| Accept a charge request | ✅ `community_charging_screen` | ✅ `POST /api/chargers/request/{id}/decision` |

"Respond to an SOS" is **not built** — the app has no nearby-SOS screen yet
(`SosService.getNearbyAlerts` exists but is unused). Add that screen first, then
gate it the same way with `ensureVerifiedForHelp(...)`.

- **Email** is considered verified when Supabase reports `email_confirmed_at`
  (true for every email/password login and all Google/Apple sign-ins).
- **Phone** is verified via the OTP flow below (`profiles.preferences.is_phone_verified`).

## ⚠️ Before launch: wire a real SMS provider

Phone OTP is currently a **dev/test scaffold**. With no `SMS_PROVIDER` env var:
- No SMS is sent.
- The accepted code is a fixed **`123456`** (override with `TEST_OTP`).
- The request endpoint logs the code and returns `{"dev_mode": true}`.

This lets you test the full gate now. To go live, in `backend/routers/auth.py`:
1. Set Cloud Run env `SMS_PROVIDER=msg91` (or `twilio`) plus the provider creds.
2. Implement delivery inside `_send_sms_otp()` (there's a `TODO(launch)` marker).
   - **MSG91** (India): auth key + approved DLT template.
   - **Twilio Verify**: account SID + Verify service SID (Twilio manages the code —
     you'd swap the local hash check for a Verify `check` call).
3. Real mode generates a random 6-digit code (10-min expiry, SHA-256 hashed in
   `profiles.preferences`).

## Deploy reminder
The backend gates + OTP endpoints live in `backend/` — **deploy to Cloud Run**
for enforcement to take effect. The app changes ship in the APK/IPA build.

## Endpoints added
- `POST /api/auth/request-phone-verification` — `{ phone_number }` (auth required)
- `POST /api/auth/verify-phone-otp` — `{ phone_number, otp }` (auth required)
- `GET /api/auth/user` now also returns `email_verified`, `phone_number`, `is_phone_verified`.
