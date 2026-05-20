# byd_launcher

A new Flutter project.

## BYD head unit build

Use the profile APK for installs that need live BYD vehicle data such as speed,
gear, TPMS, lights, and door/window state:

```sh
flutter build apk --profile
adb install -r build/app/outputs/flutter-apk/app-profile.apk
```

On this BYD/DiLink firmware, the realtime vehicle APIs are available to builds
that Android installs with the `DEBUGGABLE` package flag. Flutter debug/profile
APKs keep that flag; Flutter release APKs do not, even when the release Gradle
build type is signed with the debug key. A release APK can run the launcher UI,
but the BYDAUTO speed/TPMS/listener path is blocked by the firmware.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
