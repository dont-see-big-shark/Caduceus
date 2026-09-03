<div align="center">

<img src="assets/images/logo.png" width="96" height="96" alt="Caduceus Logo" />

# Caduceus Flutter App

A native cross-platform Flutter client for Hermes Agent.

</div>

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## iOS Simulator (Xcode 27 beta)

Xcode 27 beta replaces `Simulator.app` with `DeviceHub.app`, so `open -a Simulator`
no longer works. Use the bundled launcher instead:

```bash
cd flutter_app
./tool/launch_ios_simulator.sh "iPhone 17 Pro"
```

Then run the app against the booted simulator:

```bash
flutter run -d "iPhone 17 Pro"
```

The launcher also creates the `Simulator.app` symlink that Flutter expects under
the selected Xcode (`xcode-select -p`).

## Android (Device & Emulator)

Run on a connected Android device or running emulator:

```bash
# Debug run
flutter run -d android

# Build Release APK
flutter build apk --release

# Install to connected device
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## Windows Desktop

Run and build on Windows:

```bash
# Debug run
flutter run -d windows

# Build Release Desktop Binary
flutter build windows --release
```
