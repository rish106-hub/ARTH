# ARTH — India's First Tax Gap Intelligence App

> **Not a rupee less. Not a rupee more.**

ARTH finds every deduction you're legally entitled to under Finance Act 2025 but haven't claimed — your **tax gap**. Answer 12 questions. Get an exact rupee amount you're leaving on the table. Take action before 31 March 2026.

---

## The Problem

Most salaried Indians overpay income tax — not because of complexity, but because no tool shows them *exactly* how much they're missing and *why*. CA fees are high, generic apps give generic advice, and the ITR form doesn't tell you what you're missing.

ARTH solves this with a decision-tree engine that runs 12 targeted triggers against your income profile and surfaces only the gaps that apply to you — with the exact rupee amount.

---

## How It Works

```
12 Questions → Gap Engine → Your Tax Gap (₹)
```

1. **Income profile** — CTC, employment type, city, age
2. **Deduction scan** — Rent/HRA, 80C investments, NPS, health insurance,
   home loan, education loan, donations
3. **Regime comparison** — Old vs New regime, exact tax under each
4. **Gap cards** — Each missed deduction shown with amount, deadline, action steps
5. **Progress tracker** — Mark gaps as done, track completion to 31 March

---

## Tax Coverage (Finance Act 2025 / FY 2025-26)

| Trigger | Section | Max Gap |
|---------|---------|---------|
| 80C investments | Sec 80C | ₹1,50,000 |
| Extra NPS contribution | Sec 80CCD(1B) | ₹50,000 |
| Health insurance — self | Sec 80D | ₹25,000 / ₹50,000 (60+) |
| Health insurance — parents | Sec 80D | ₹25,000 / ₹50,000 (60+) |
| Rent without HRA | Sec 80GG | ₹60,000 |
| Home loan interest | Sec 24(b) | ₹2,00,000 |
| Education loan interest | Sec 80E | Actual |
| Savings interest | Sec 80TTA/TTB | ₹10,000 / ₹50,000 (60+) |
| Employer NPS routing | Sec 80CCD(2) | Informational |
| Regime switch | Both regimes | Actual savings |

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter 3.x (Android) |
| State | Riverpod (NotifierProvider) |
| Navigation | go_router |
| Backend | Firebase (Firestore + Auth + Remote Config) |
| Database | Firestore / SQL schema in `database/schema.sql` |
| Local storage | shared_preferences (offline-first) |
| CI/CD | GitHub Actions → Google Play Store |
| Auth | Manual account + Google Sign-In (feature-flagged) |

### Why Firebase over Supabase

Firebase Firestore is used instead of Supabase because:
- Firebase has servers in the **Mumbai region** — sub-50ms latency from India
- Supabase free tier has no India region (300–500ms latency)
- Firebase Spark plan is **permanently free** at the scale of a personal finance app (50K reads/day, 20K writes/day)
- Firebase Auth handles anonymous → Google account upgrade without losing data

---

## Architecture

```
lib/
├── engine/
│   ├── tax_engine.dart        # Old + New regime calculation (Finance Act 2025)
│   └── gap_finder.dart        # 12 decision-tree triggers (T01–T12)
├── models/
│   ├── user_profile.dart      # 12 onboarding fields
│   ├── user_account.dart      # Auth identity (manual / Google)
│   ├── gap_card.dart          # Deduction gap data model
│   └── tax_result.dart        # Computed tax result
├── providers/
│   ├── auth_provider.dart     # Auth state (Riverpod)
│   ├── user_profile_provider.dart
│   ├── tax_result_provider.dart
│   └── feature_flags_provider.dart  # Remote Config flags
├── services/
│   ├── auth_service.dart      # Local auth + Firebase anonymous sign-in
│   ├── cloud_sync_service.dart # Firestore sync (offline-first)
│   └── google_auth_service.dart # Google Sign-In (feature-flagged)
├── screens/                   # S00–S12 screens
└── assets/
    └── tax_data.json          # Finance Act 2025 slab + trigger data
```

---

## Getting Started

### Prerequisites
- Flutter 3.x — [Install Flutter](https://docs.flutter.dev/get-started/install/macos)
- Android SDK (API 21+)
- A Firebase project — [console.firebase.google.com](https://console.firebase.google.com)

### Local Setup

```bash
# 1. Clone
git clone https://github.com/YOUR_ORG/arth.git && cd arth

# 2. Install dependencies
flutter pub get

# 3. Configure Firebase (one-time)
dart pub global activate flutterfire_cli
flutterfire configure --project=arth-taxgap
# → generates lib/firebase_options.dart and android/app/google-services.json

# 4. Run on device / emulator
flutter run
```

### Firebase Setup

1. Create project `arth-taxgap` at [console.firebase.google.com](https://console.firebase.google.com)
2. Enable **Firestore** (start in production mode)
3. Enable **Firebase Auth** → Anonymous + Google providers
4. Enable **Remote Config** → add key `google_sign_in_enabled` = `false`
5. Enable **Firebase Messaging** (for deadline reminders)
6. Upload `firebase/firestore.rules` via Firebase CLI:
   ```bash
   firebase deploy --only firestore:rules
   ```
7. Add your Android SHA-1 to the Firebase project settings:
   ```bash
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey \
           -storepass android -keypass android
   ```

---

## Building for Production

### 1. Generate a keystore (one-time)
```bash
keytool -genkey -v -keystore android/app/arth-release.jks -alias arth \
        -keyalg RSA -keysize 2048 -validity 10000
```

### 2. Create `android/key.properties` (from template)
```bash
cp android/key.properties.template android/key.properties
# Edit key.properties with your passwords
```

### 3. Build release APK / App Bundle
```bash
flutter build appbundle --release        # for Play Store
flutter build apk --release --split-per-abi  # for direct distribution
```

---

## CI/CD Pipeline

| Workflow | Trigger | Action |
|----------|---------|--------|
| `ci.yml` | Push to `main` / PR | Lint + test + debug APK |
| `release.yml` | Push git tag `v*.*.*` | Release AAB → Play Store internal track |

### First Release

```bash
git tag v1.0.0
git push origin v1.0.0
```

The `release.yml` workflow requires these **GitHub Secrets** (Settings → Secrets → Actions):

| Secret | Description |
|--------|-------------|
| `GOOGLE_SERVICES_JSON` | base64-encoded `google-services.json` |
| `KEYSTORE_BASE64` | base64-encoded `.jks` keystore file |
| `KEYSTORE_STORE_PASSWORD` | keystore store password |
| `KEYSTORE_KEY_PASSWORD` | key password |
| `KEYSTORE_KEY_ALIAS` | key alias (e.g. `arth`) |
| `PLAY_STORE_SERVICE_ACCOUNT_JSON` | base64-encoded Play Console service account |

To base64-encode a file:
```bash
base64 -i android/app/google-services.json | tr -d '\n'
```

---

## Enabling Google Sign-In

Google Sign-In is implemented and feature-flagged via Firebase Remote Config.
The button renders as disabled ("Coming Soon") until you flip the flag.

**To enable in production:**
1. Firebase Console → Remote Config
2. Set `google_sign_in_enabled` = `true`
3. Publish changes

**SHA-1 required for Google Sign-In:**
```bash
# Debug (for development)
keytool -list -v -keystore ~/.android/debug.keystore \
        -alias androiddebugkey -storepass android

# Release (for production)
keytool -list -v -keystore android/app/arth-release.jks -alias arth
```
Add both SHA-1 fingerprints in Firebase Console → Project Settings → Android app.

---

## Database

Firestore document schema is mirrored as a PostgreSQL-compatible SQL schema in:
```
database/schema.sql
```

If you migrate to a relational database (Neon, PlanetScale, Railway), the SQL schema is ready to use.

---

## Tax Logic

All calculations are based on **Finance Act 2025 / FY 2025-26 / AY 2026-27**:

- New regime slabs: 0% up to ₹4L, then 5%/10%/15%/20%/25%/30%
- 87A rebate: New ≤ ₹12L → up to ₹60,000 rebate; Old ≤ ₹5L → up to ₹12,500
- Standard deduction: ₹75,000 (new) / ₹50,000 (old)
- Surcharge: only above ₹50L income
- Cess: 4% on (tax + surcharge)
- HRA metro cities (per IT Act Rule 2A): Delhi, Mumbai, Chennai, Kolkata only

---

## Deployment Checklist

- [ ] `flutterfire configure` — generates `firebase_options.dart`
- [ ] `google-services.json` in `android/app/`
- [ ] Firestore security rules deployed (`firebase deploy --only firestore:rules`)
- [ ] SHA-1 fingerprints added to Firebase project (debug + release)
- [ ] Google Play Console — app created, package `com.arth.taxgap`
- [ ] Keystore generated and `key.properties` created
- [ ] GitHub Secrets configured (6 secrets listed above)
- [ ] First tag pushed: `git tag v1.0.0 && git push origin v1.0.0`
- [ ] Internal testing on Play Store → promote to production

---

## License

Private — All rights reserved. © 2025 ARTH.
