# SDMS Mobile App

Flutter app for the Document Management System (Android + iOS). It uses the same API as the web
(`https://sdms-api.vercel.app/api/admin`) and the same roles and rules.

## Run

```bash
flutter pub get
flutter run
```

Every active web account can sign in to the app with the same email and password.

## Settings

`lib/core/env.dart` holds the API host and API key. They can be overridden without editing code:

```bash
flutter run --dart-define=API_HOST=https://sdms-api.vercel.app --dart-define=API_KEY=xxxx
```

## Screens

- Login (`/auth/login/app`), role-based bottom navigation
- Home: month + date-field filters, summary tiles, charts, latest new documents, my office chain
- ឯកសារចូល / ឯកសារចេញ: lists with search, paging, filters
- Document detail: information, files (PDF / image viewer), receive, forward, return, finish, send, tracking
- Write / sign on a PDF (pen button in the file viewer): text boxes, pen, signature; saves the signed PDF back to the document (same rules as the web). Pages you write on become images; untouched pages stay as they are.
- Create / edit document: files go straight to Cloudinary (no size limit from the API)
- Account: profile, office chain, change password, logout
- Admin (super admin): users (add, edit, delete, reset password) and the 7 master-data lists

Not in this version yet: push notifications.

## Push notifications (FCM)

The phone is told when a document arrives (send / forward / return) or is finished.
It is **off until Firebase is set up** – without the files below the app works as before.

1. Firebase console → create a project → add an **Android app** with package `kh.gov.mef.sdms_app`
   → download `google-services.json` into `android/app/`.
2. (iOS) add an iOS app with bundle id `kh.gov.mef.sdmsApp` (check Xcode) → put `GoogleService-Info.plist`
   into `ios/Runner/` through Xcode, upload an APNs key in Firebase → Project settings → Cloud Messaging,
   in Xcode → Signing & Capabilities add **Push Notifications** and **Background Modes → Remote notifications**,
   then run with `--dart-define=PUSH_IOS=true`.
3. API (Vercel): Firebase console → Project settings → Service accounts → *Generate new private key*.
   Put the whole JSON (or its base64) in the Vercel env var `FIREBASE_SERVICE_ACCOUNT`, run `npm install`
   in `sdms_api` (adds `firebase-admin`) and redeploy.

The phone registers its token after login (`POST /api/admin/push/register`) and removes it on sign-out.
Tapping a notification opens that document.
