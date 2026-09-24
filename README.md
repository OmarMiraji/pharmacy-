# Phyimacy

Windows-first Pharmacy Management System built with Flutter, Dart, and Firebase.

## Current foundation

- Firestore collection design: [docs/firestore-schema.md](docs/firestore-schema.md)
- Firestore security rules: `firestore.rules`
- Firestore indexes: `firestore.indexes.json`

This first version does not use Firebase Cloud Storage. Medicines and transactions
store text, numbers, timestamps, and references in Cloud Firestore. Images and
videos are intentionally out of scope until a paid storage option is approved.

## Users, credentials, and permissions

Create every Firebase Authentication user directly in the Firebase Console
under **Authentication > Users > Add user**. The email and password therefore
never appear in this repository or in the Flutter source code. The app only
performs sign-in and sign-out.

After creating a user, copy the Firebase Auth UID and create `users/{uid}` in
Firestore with `displayName`, `email`, `role`, `permissions`, and `isActive`.
Firestore rules enforce the permissions map. Only an admin can change role,
permissions, or account status; passwords remain managed by Firebase Auth.

## Local prerequisites

Install the following before creating the Flutter app:

1. Flutter stable SDK with Windows desktop support.
2. Visual Studio 2022 with **Desktop development with C++**.
3. Firebase CLI and FlutterFire CLI.
4. A Firebase project with Authentication, Firestore, and Storage enabled.

Verify the toolchain:

```powershell
flutter doctor -v
firebase --version
flutterfire --version
```

## Next setup commands

Run these commands from this folder after installing the prerequisites:

```powershell
flutter create --platforms=windows .
flutter pub add firebase_core firebase_auth cloud_firestore firebase_storage
firebase login
firebase use --add
flutterfire configure --platforms=windows
firebase deploy --only firestore:rules,firestore:indexes,storage
flutter run -d windows
```

Do not deploy the rules until the first admin user has been created in Firebase Authentication and a matching `users/{uid}` document has been seeded with `role: "admin"`.
