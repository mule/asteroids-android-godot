# Asteroids Android Godot Practice

This repository is a small practice project for learning how to build Android games with Godot while using Codex as an implementation partner. The example game is Asteroids: fly the ship, avoid asteroids, shoot them into smaller pieces, and keep playing through restartable rounds.

The project is intentionally issue-driven. Each feature should be small enough to inspect, implement, verify, and review in one focused branch.

## Project Details

- Engine: Godot 4.7.x. The project file declares `config/features=PackedStringArray("4.7", "Mobile")`.
- Main scene: `res://scenes/game/Main.tscn`.
- Android package: `com.japurane.asteroids`.
- Android app name: `Asteroids`.
- Orientation: landscape.
- Export preset: `Android`, configured for debug APK builds.

## Open The Project

Install Godot 4.7.x, then open this checkout from the editor:

```sh
/home/japurane/.local/bin/godot --editor --path .
```

From the editor, press Play to run the configured main scene.

## Desktop Iteration

For quick local playtesting on desktop:

```sh
/home/japurane/.local/bin/godot --path .
```

Current keyboard controls:

- Rotate left: `Left Arrow` or `A`
- Rotate right: `Right Arrow` or `D`
- Thrust: `Up Arrow` or `W`
- Shoot: `Space`
- Pause: `P` or `Esc`
- Restart: `R` or `Enter`

The game also includes touch controls for Android testing.

## Android Build And Install

The Android export preset is already committed in `export_presets.cfg`. Local Android SDK and Java SDK paths still need to be configured in Godot on each machine.

Use the Android guide for the full setup and verified commands:

- [Android export guide](docs/android-export.md)

Short version:

```sh
mkdir -p builds/android
/home/japurane/.local/bin/godot --headless --path . --export-debug Android builds/android/asteroids-debug.apk
/home/japurane/Android/Sdk/platform-tools/adb install -r builds/android/asteroids-debug.apk
/home/japurane/Android/Sdk/platform-tools/adb shell monkey -p com.japurane.asteroids -c android.intent.category.LAUNCHER 1
```

Generated APKs under `builds/android/` are ignored by Git.

## Codex Workflow

Use the project as a loop for practicing small, reviewable game development tasks:

1. Pick one open GitHub issue from the task list.
2. Ask Codex to inspect the current repo and issue before changing files.
3. Create or switch to a feature branch for that task.
4. Implement the smallest complete version of the feature.
5. Run the relevant verification: desktop Godot launch, Android export, APK install, or device launch.
6. Commit only the scoped source and documentation changes.
7. Open a pull request that names what changed and what was tested.
8. Merge after the PR is reviewed or confirmed.

Prefer leaving generated files, editor caches, and local IDE state out of commits unless they are Godot source metadata required by the project.

## Roadmap

Planning lives in GitHub issues:

- [Epic: Build a playable Asteroids Android practice game in Godot](https://github.com/mule/asteroids-android-godot/issues/11)
- [Epic: Build a reproducible AI-assisted game asset pipeline](https://github.com/mule/asteroids-android-godot/issues/22)
- [Epic: Scroll the game across a large sector with fields, bodies, stations, and ships](https://github.com/mule/asteroids-android-godot/issues/43)
- [Open task list](https://github.com/mule/asteroids-android-godot/issues)

Asset pipeline conventions live in:

- [Asset pipeline contract](docs/asset-pipeline.md)
- [Art style guide](docs/art-style-guide.md)
