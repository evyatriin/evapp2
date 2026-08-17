# Google & Apple Sign-In — Setup Checklist

The app code for OAuth is done. The **"Continue with Google / Apple"** buttons on
the login and signup screens call Supabase OAuth and route the user home (or into
onboarding) when the session comes back via a deep link.

Until the steps below are completed in your dashboards, the buttons will show a
friendly *"this sign-in option is not enabled yet"* message instead of working —
nothing crashes.

**Redirect URI used by the app** (already wired into the native config and
`lib/src/features/authentication/auth_service.dart` → `kOAuthRedirectUri`):

```
io.supabase.evraahein://login-callback/
```

Already configured in code for you:
- Android deep link — `android/app/src/main/AndroidManifest.xml` (VIEW intent-filter).
- iOS URL scheme — `ios/Runner/Info.plist` (`CFBundleURLTypes`).

---

## 1. Supabase dashboard (required for both providers)

Project: `mzxwbfpxmyjmbfhosgkk`

1. **Authentication → URL Configuration → Redirect URLs** — add:
   ```
   io.supabase.evraahein://login-callback/
   ```
2. **Authentication → Providers → Google** — toggle **Enabled**, paste the Google
   **Client ID** and **Client Secret** from step 2 below.
3. **Authentication → Providers → Apple** — toggle **Enabled**, paste the Apple
   **Services ID**, **Team ID**, **Key ID**, and the **private key** from step 3.

Supabase's own callback URL (needed in the Google/Apple consoles below) is:
```
https://mzxwbfpxmyjmbfhosgkk.supabase.co/auth/v1/callback
```

## 2. Google (Google Cloud Console → APIs & Services → Credentials)

1. Configure the **OAuth consent screen** (External), add your support email and
   the app name "EVraahein".
2. Create an **OAuth client ID → Web application**:
   - Authorized redirect URI:
     `https://mzxwbfpxmyjmbfhosgkk.supabase.co/auth/v1/callback`
   - Copy the **Client ID** and **Client Secret** → paste into Supabase (step 1.2).
3. For Android release/Play builds, also add the app's **SHA-1 / SHA-256**
   fingerprints under an **Android OAuth client** (or via Play App Signing).

## 3. Apple (only needed to ship "Continue with Apple", required by App Store if you offer other social logins on iOS)

1. Apple Developer → **Certificates, Identifiers & Profiles**:
   - Create/confirm an **App ID** with **Sign in with Apple** capability.
   - Create a **Services ID**; set its **Return URL** to
     `https://mzxwbfpxmyjmbfhosgkk.supabase.co/auth/v1/callback`.
   - Create a **Sign in with Apple key**, download the `.p8`.
2. In **Xcode → Runner → Signing & Capabilities**, add the
   **Sign in with Apple** capability to the Runner target.
3. Paste the Services ID / Team ID / Key ID / `.p8` contents into Supabase (step 1.3).

---

## How it works in the app (for reference)

- `auth_service.dart` → `signInWithOAuth(provider)` launches the provider page.
- The provider redirects to the Supabase callback, which redirects to
  `io.supabase.evraahein://login-callback/`.
- The OS reopens the app; `supabase_flutter` catches the link and sets the
  session.
- `user_provider.dart` listens to `onAuthStateChange`; on `signedIn` it loads the
  profile, and `OAuthButtons` routes the user to `/onboarding` (new) or `/` (returning).

The same `onAuthStateChange` listener is also what now keeps email/password users
logged in across app restarts (the session is persisted and auto-refreshed).
