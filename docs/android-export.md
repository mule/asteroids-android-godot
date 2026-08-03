# Android export

This project uses the Godot Android preset named `Android`.

The Android package is `com.japurane.asteroids`, the app label is `Asteroids`, and the project is configured for landscape orientation.

## Local prerequisites

- Godot 4.7.1 with Android export templates installed.
- Android SDK installed locally.
- Android SDK paths configured in the Godot editor settings for this machine.
- A connected Android device or running emulator for install verification.

On this workstation, the verified local paths are:

- Android SDK: `/home/japurane/Android/Sdk`
- Java SDK: `/usr/lib/jvm/java-17-openjdk-amd64`

## Export a debug APK

```sh
mkdir -p builds/android
/home/japurane/.local/bin/godot --headless --path . --export-debug Android builds/android/asteroids-debug.apk
```

## Install on a connected device

```sh
/home/japurane/Android/Sdk/platform-tools/adb devices
/home/japurane/Android/Sdk/platform-tools/adb install -r builds/android/asteroids-debug.apk
```

If `adb devices` shows no device, connect a phone with USB debugging enabled or start an Android emulator before installing.

## Launch

```sh
/home/japurane/Android/Sdk/platform-tools/adb shell monkey -p com.japurane.asteroids -c android.intent.category.LAUNCHER 1
```

The generated APK is ignored by Git.

## Current local verification

- Debug APK export succeeds at `builds/android/asteroids-debug.apk`.
- APK signature verification passes.
- Install succeeds on Samsung tablet `SM_X710` (`R52Y202C7LJ`).
- Launch succeeds for package `com.japurane.asteroids`.
