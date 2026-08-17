# App Store Metadata — EVraahein

> Source of truth for both Apple App Store Connect and Google Play Console.
> Keep this file updated before every release.

---

## Identity

| Field | Value |
|-------|-------|
| **App Name** | EVraahein |
| **Bundle ID (iOS)** | com.evraahein.app *(set in Xcode)* |
| **Package Name (Android)** | com.evraahein.app *(set in build.gradle)* |
| **Version** | 1.0.0 |
| **Build Number** | 1 |
| **Category** | Navigation / Travel |
| **Secondary Category** | Utilities |
| **Content Rating** | 4+ / Everyone |
| **Pricing** | Free |

---

## Short Description
*(max 80 characters — Apple Subtitle / Google Play Short Description)*

```
EV navigation, charging finder & OBD battery insights — all in one.
```

---

## Full Description
*(max 4000 characters — Apple / Google Play Long Description)*

```
EVraahein is the all-in-one companion for electric vehicle drivers in India.
Plan smarter trips, find chargers on the way, monitor your battery live —
all from a single app.

─────────────────────────────────────────
SMART EV ROUTING
─────────────────────────────────────────
• Plan routes that automatically include charging stops based on your
  battery level and vehicle range.
• Real-time elevation data ensures accurate range predictions on hilly terrain.
• Supports every major Indian EV — Tata Nexon EV, Ather 450X, Ola S1,
  Mahindra XUV400, MG ZS EV, and more.
• Save and replay your favourite routes.

─────────────────────────────────────────
CHARGING STATION FINDER
─────────────────────────────────────────
• Discover 15,000+ charging stations across India via OpenChargeMap,
  Google Maps, and Beckn network.
• Filter by connector type (CCS2, CHAdeMO, Type 2, Bharat AC/DC),
  power rating, and network.
• Scan QR codes at Beckn-enabled stations to start a session directly
  in the app — no separate app needed.
• Postpaid metered billing: pay only for what you charge via UPI.

─────────────────────────────────────────
LIVE OBD-II BATTERY INSIGHTS
─────────────────────────────────────────
• Connect your EV's OBD-II port via Bluetooth (BLE or Classic).
• Monitor state of charge, voltage, current, motor temperature,
  and GPS speed in real time.
• Get AI-powered range estimates based on your actual driving patterns.
• Track charging history and energy efficiency over time.
• Works offline — Bluetooth data never requires an internet connection.

─────────────────────────────────────────
SAFETY & COMMUNITY
─────────────────────────────────────────
• SOS emergency button with one-tap location sharing.
• Community trip reports and charger check-ins.
• News and updates from the Indian EV ecosystem.

─────────────────────────────────────────
PRIVACY-FIRST
─────────────────────────────────────────
• Location is used only while the app is open — never tracked in the background.
• OBD data stays on your device; only aggregated, anonymised statistics
  are used to improve range models.
• No location data is sold or shared with advertisers.

─────────────────────────────────────────
DESIGNED FOR INDIA
─────────────────────────────────────────
• Indian EV profiles with accurate battery chemistry models.
• Works on Indian road networks, including highways and city streets.
• UPI payments for seamless Beckn charging sessions.

Download EVraahein and drive electric with confidence.
```

---

## Keywords

### Apple App Store (max 100 characters, comma-separated, no spaces after commas)
```
EV,electric vehicle,charging station,OBD,battery,route planner,India,Beckn,charger finder,range
```

### Google Play Tags (up to 5 tags)
```
Electric Vehicle
EV Charging
Route Planner
OBD Scanner
Battery Monitor
```

---

## What's New (Version 1.0.0)

```
Initial release of EVraahein!

• Smart EV route planning with automatic charging stops
• 15,000+ charging stations across India
• Live OBD-II battery monitoring via Bluetooth
• Beckn network integration — scan & charge with UPI
• SOS emergency location sharing
• Indian EV profiles: Tata Nexon, Ather, Ola, Mahindra, MG
```

---

## Screenshots Required

### iPhone (6.9" — iPhone 16 Pro Max, required)
1. Map view with route and charging stops marked
2. Charger list view with connector types and availability
3. OBD telemetry dashboard — live battery metrics
4. QR scan screen with charging station details
5. Route planning screen with range overlay

### iPhone (6.5" — iPhone 14 Plus, required)
*(Same content, different device frame)*

### iPad (12.9" — iPad Pro, required if supporting iPad)
*(Optional — app runs on iPad but is not optimised)*

### Android Phone (required)
1. Map view with route and stops
2. Charger discovery with filters
3. OBD live monitoring
4. Beckn charging QR scan
5. Session screen with live energy metrics

---

## App Store-Specific Fields

### Apple App Store Connect

| Field | Value |
|-------|-------|
| **Support URL** | https://evraahein.app/support *(or mailto:pidaparthy@gmail.com)* |
| **Privacy Policy URL** | https://evraahein.app/privacy *(must be live HTTPS URL)* |
| **Marketing URL** | *(optional)* |
| **Age Rating** | 4+ |
| **Made for Kids** | No |
| **Pricing** | Free |
| **Availability** | India (initial), expand later |

#### Privacy Nutrition Labels (Data Used to Track You)
- None

#### Data Linked to You
- Location (route planning, charger search)
- Contact info (email — account creation)
- Usage data (crash reports — Sentry)
- Photos/videos (charger check-in photos, QR scan)

#### Data Not Linked to You
- Diagnostics (crash reports)

### Google Play Console

| Field | Value |
|-------|-------|
| **App Category** | Travel & Navigation |
| **Tags** | Electric Vehicle, Navigation, OBD |
| **Contact Email** | pidaparthy@gmail.com |
| **Privacy Policy URL** | https://evraahein.app/privacy |
| **Target Audience** | 18+ |
| **Contains Ads** | Yes (AdMob) |
| **Data Safety** | Location (approximate + precise), Bluetooth (device info), Photos (optional) |

---

## Permissions Rationale (for Review Teams)

| Permission | Why Needed | When Requested |
|-----------|-----------|---------------|
| Location (Precise) | Center map on user, find nearby chargers, calculate routes | On first map use |
| Location (Approximate) | Fallback if precise unavailable | Same |
| Bluetooth Scan | Discover OBD-II adapter nearby | OBD screen, user-initiated |
| Bluetooth Connect | Connect to and read data from OBD-II adapter | OBD screen, user-initiated |
| Camera | Scan QR codes at Beckn charging stations | Charging QR scan screen |
| Photo Library Read | Attach images to charger check-ins | Check-in form, user-initiated |
| Photo Library Write | Save exported trip summaries | Export action, user-initiated |

---

## App Review Notes (paste into Review Notes field)

```
Test Account:
  Email: reviewer@evraahein.app
  Password: EVreview2026!

Key Flows to Test:
1. Route Planning: Tap the search bar → type "Delhi to Agra" → select EV route
   → charging stops appear automatically on the route.
2. Charger Finder: Bottom sheet → Chargers tab → list of stations appears.
3. OBD Scanner: Tap OBD icon in drawer → Scan → (no real OBD device needed;
   the app handles "no device found" gracefully with an empty state).
4. Beckn Charging: Feature is behind a server-side flag (BECKN_CHARGING_ENABLED).
   It is disabled in the test environment and will not appear in the UI during review.

Bluetooth Note:
  Bluetooth is optional. The app works fully without it; OBD features
  are only available after the user pairs an OBD-II adapter.

Location Note:
  Location permission is requested on first map interaction, not at app launch.
  The user can dismiss and still use non-location features.
```

---

## Icon Specs Checklist

- [ ] 1024×1024 PNG (no alpha, no rounded corners — Apple adds them)
- [ ] 512×512 PNG (Google Play)
- [ ] All sizes auto-generated via `flutter_launcher_icons` from `assets/icon/icon.png`
- [ ] Adaptive icon foreground + background (Android 8+) — `assets/icon/icon_foreground.png`

---

## Release Checklist

- [ ] Version bumped in `pubspec.yaml`
- [ ] Build number incremented (`+N`)
- [ ] `flutter build ipa --release` passes without warnings
- [ ] `flutter build appbundle --release` passes without warnings
- [ ] Privacy policy hosted at a live HTTPS URL
- [ ] AdMob App ID replaced with production ID (currently test ID in `Info.plist`)
- [ ] Google Maps API key restricted to production bundle ID
- [ ] Sentry DSN set in production environment variables
- [ ] Backend `APP_ENV=production` (disables `/docs`, `/redoc`)
- [ ] Test account credentials provided in Review Notes
- [ ] Screenshots captured from physical device (not simulator)
