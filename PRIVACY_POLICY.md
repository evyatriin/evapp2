# Privacy Policy — EVraahein

**Last updated: May 17, 2026**
**Effective date: May 17, 2026**

---

## 1. Who We Are

EVraahein ("we", "us", "our") is an electric vehicle routing and charging application. Our registered contact for privacy matters is: **pidaparthy@gmail.com**

---

## 2. What Data We Collect and Why

### 2.1 Location Data
**What:** Precise GPS coordinates while the app is in use.  
**Why:** To center the map on your position, find nearby charging stations, calculate routes, and provide turn-by-turn navigation guidance.  
**Stored:** Location is processed in real-time on-device. Route coordinates are sent to our backend only while calculating a route. We do not log or store your location history on our servers.  
**Legal basis:** Your explicit in-app permission (required before first use).

### 2.2 Bluetooth Data
**What:** Nearby Bluetooth device names and hardware addresses during scanning; OBD-II data stream (battery voltage, state of charge, speed, elevation, motor temperature, energy consumption).  
**Why:** To connect to your vehicle's OBD-II adapter and surface battery health, range estimates, and charging predictions.  
**Stored:** OBD telemetry is stored locally on your device. Aggregated, anonymised trip statistics (distance, energy used, estimated SOC) may be sent to our backend to improve range prediction models.  
**Legal basis:** Your explicit in-app permission (required before first use).

### 2.3 Account Data
**What:** Email address and password (hashed — we never see plaintext passwords); optional display name and profile photo.  
**Why:** To create and authenticate your account, save your favourite routes and chargers, and enable SOS emergency features.  
**Stored:** Managed by Supabase (EU region). Passwords are bcrypt-hashed and never transmitted or stored in plaintext.

### 2.4 Usage Data
**What:** Routes searched, chargers viewed, sessions started/ended, feature interactions.  
**Why:** To improve app functionality, debug errors (via Sentry crash reporting), and understand which features are most useful.  
**Stored:** Anonymised event logs retained for 90 days. Crash reports retained for 30 days.

### 2.5 Camera and Photos
**What:** Camera access when you choose to scan a charger QR code; photo library access if you attach images to a charging check-in.  
**Why:** QR scanning triggers the charger-start flow. Photos are uploaded to your private account storage only when you explicitly share them.  
**Stored:** Uploaded photos are stored in your account's private bucket (Supabase Storage) and are never shared publicly without your action.

### 2.6 Device Information
**What:** Device model, OS version, app version, crash context.  
**Why:** To debug platform-specific issues and ensure compatibility.  
**Stored:** Sent to Sentry for crash analysis only. Not linked to your identity.

---

## 3. What We Do NOT Collect

- We **do not** sell your data to third parties.
- We **do not** share your precise location with advertisers.
- We **do not** track your location in the background without your explicit consent.
- We **do not** read your contacts, messages, or other apps.
- We **do not** use third-party analytics SDKs beyond Sentry crash reporting.

---

## 4. Advertising

EVraahein may display ads served by **Google AdMob**. AdMob may collect advertising IDs and serve personalised ads based on your broader device activity, subject to Google's own privacy policy. You can opt out of personalised ads in your device settings:

- **Android:** Settings → Google → Ads → Opt out of Ads Personalisation
- **iOS:** Settings → Privacy & Security → Apple Advertising → Personalised Ads (off)

---

## 5. Data Sharing

| Recipient | Purpose | Data Shared |
|-----------|---------|-------------|
| Supabase (EU) | Database & auth | Account data, saved routes, charger history |
| Google Maps | Map tiles & geocoding | Map viewport coordinates, search queries |
| HERE Maps | Routing engine | Origin/destination coordinates |
| OpenChargeMap | Charger data | Bounding box search coordinates |
| Sentry | Crash reporting | Device info, anonymised stack traces |
| Google AdMob | Ads | Advertising ID (opt-out available) |

We do not share data with any other parties. All vendors are contractually bound to process data only for the purposes listed above.

---

## 6. Data Retention

| Data Type | Retention |
|-----------|-----------|
| Account data | Until you delete your account |
| Saved routes & chargers | Until you delete them or your account |
| Crash reports | 30 days |
| Usage event logs | 90 days |
| OBD telemetry (local) | Until you clear app data |

---

## 7. Your Rights

You have the right to:

- **Access** — Request a copy of all personal data we hold about you.
- **Rectification** — Correct inaccurate data in your profile.
- **Erasure** — Delete your account and all associated data from Settings → Account → Delete Account.
- **Portability** — Export your saved routes and charging history in JSON format.
- **Restriction** — Revoke individual permissions (location, Bluetooth, camera) at any time in device Settings without uninstalling the app.

To exercise any of these rights, email **pidaparthy@gmail.com** with subject "Privacy Request". We will respond within 30 days.

---

## 8. Children

EVraahein is not directed at children under 13 (US) or 16 (EU/UK). We do not knowingly collect personal information from children. If you believe a child has created an account, contact us and we will delete it promptly.

---

## 9. Security

- All data in transit uses TLS 1.2+.
- Passwords are bcrypt-hashed (never stored in plaintext).
- QR codes are HMAC-SHA256 signed to prevent spoofing.
- JWT tokens expire after 1 hour; refresh tokens are rotated on each use.
- We conduct regular security reviews of our backend.

---

## 10. Changes to This Policy

We will notify you of material changes via an in-app banner at least 14 days before changes take effect. The "Last updated" date at the top of this document will always reflect the current version.

---

## 11. Contact

**Email:** pidaparthy@gmail.com  
**Subject line for privacy queries:** "EVraahein Privacy"

For EU/UK users, if you are unsatisfied with our response you have the right to lodge a complaint with your local Data Protection Authority.

---

*This policy applies to the EVraahein mobile app on iOS and Android.*
