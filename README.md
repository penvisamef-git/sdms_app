# SDMS Mobile App

Flutter app for the Document Management System (Android + iOS). It uses the same API as the web
(`https://sdms-api.vercel.app/api/admin`) and the same roles and rules.

## Run

```bash
flutter pub get
flutter run
```

Accounts must have **"អនុញ្ញាតឱ្យចូលប្រើក្នុង Mobile App"** switched on (User form on the web).

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
