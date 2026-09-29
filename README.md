# Square Number

Square Number is a falling-number puzzle game built with Flutter. Guide each active square into a match, chain clears as the board settles, and keep the five-column stack below the top border. The app supports Android, iOS, web, Windows, Linux, and macOS from one adaptive codebase.

## Gameplay

1. Select **Start**, then drag the falling square sideways or down. Releasing it snaps it to one of five columns; placed squares cannot be moved.
2. Clear at least two equal squares that touch at an edge or corner, or clear an orthogonally connected chain of at least three unique values where each neighboring value differs by exactly one. Consecutive chains can turn corners, but a repeated value inside a chain (for example `1-2-1`) does not count.
3. Each clear scores `(sum of removed values) x (number of removed squares)`.
4. When a clear removes support, newly falling squares can trigger another clear. Each clear in that cascade receives an increasing multiplier, which resets when the next square appears. Floating score indicators show each clear as it lands.
5. Effective speed increases by `0.10x` every 500 points and is capped at `1.50x`.
6. The run ends when a placed square extends above the top border.

## Controls And Saved Runs

- **Start/Pause** starts or pauses the current board. On narrow screens these commands use icon buttons with tooltips.
- **New Game** records a positive current score in the device-local top 10, clears the board, and immediately starts a new run.
- Moving the app to the background pauses the game and saves a non-empty board. The saved board and score are restored in a paused state on the next launch.
- Opening Settings on a phone pauses an active run.
- Changing the generated number range starts a fresh board. Base speed and theme changes apply directly.
- Phone gameplay is kept in portrait after a run starts. Tablet and desktop layouts support the available orientations.
- The current score appears in Score History only when it qualifies for the top 10. It is marked **Current** until the run ends; completed entries retain their effective speed and Phone, Tablet, or Desktop layout label.

## Features

- Two matching systems: edge-or-corner equal groups and turning orthogonal consecutive chains
- Fixed five-column board on phone, tablet, and desktop, with square size derived from the board width
- Cascade multipliers with floating point indicators
- Device-local highest score, paused board, and top-10 completed-run history
- Live top-10 preview when the current score qualifies
- Configurable base speed from `0.20x` to `1.50x`
- Configurable minimum and maximum generated values
- System, light, and dark themes
- Adaptive phone, tablet, and desktop layouts
- In-app feedback and bug-report form with app diagnostics
- Hosted-submission viewer in the Information tab
- Built-in How to Play reference in the Help tab

Game state and score data use local preferences and do not require an account. The Information tab connects to the configured support host when sending feedback or loading hosted submissions.

## Store Listing

Google Play copy is maintained in [`store_listing/`](store_listing/):

- [`store_listing/google_play_short_synopsis.txt`](store_listing/google_play_short_synopsis.txt) — the short description used on the store listing.
- [`store_listing/google_play_long_synopsis.txt`](store_listing/google_play_long_synopsis.txt) — the full description, kept within the 4000-character Google Play limit.

`assets/play_store_512.png` is shipped as a Flutter asset so the same artwork is reused for web and packaging.

## Tech Stack

- Flutter
- Dart SDK 3.12+
- Material 3
- `shared_preferences` for local board, best score, and top-10 history persistence
- `package_info_plus` for resolving the on-device package name in support submissions
- `http` for posting feedback and loading hosted submissions
- `msix` (dev dependency) for Windows Store packaging

## Getting Started

### Prerequisites

- Flutter SDK installed and available in PATH
- A supported target toolchain (Android Studio, Xcode, Visual Studio for Windows desktop, etc.)

### Install Dependencies

```powershell
flutter pub get
```

### Run in Debug Mode

```powershell
flutter run
```

## Build Targets

The project includes task definitions for common release builds.

### Android APK (Release)

```powershell
flutter build apk --release
```

### Android App Bundle (Release)

```powershell
flutter build appbundle --release
```

### Web

```powershell
flutter build web
```

### Windows

```powershell
flutter build windows
```

### MSIX (Windows Package)

```powershell
dart run msix:create --build-windows=false
```

## Android Signing Notes

- Release signing is configured in `android/app/build.gradle.kts` and reads values from `android/key.properties`.
- On Windows, use forward slashes for the `storeFile` path in `key.properties`.
- Verify signing setup with:

```powershell
android/gradlew.bat :app:signingReport
```

## Project Structure

- `lib/main.dart`: app entry point
- `lib/app/main_app.dart`: adaptive layout, status, score history integration
- `lib/features/game/widgets/falling_squares_area.dart`: game loop, spawning, collision, clear logic, scoring
- `lib/features/settings/widgets/settings_tab.dart`: Controls, Score History, Information, and Help tabs
- `lib/contact/contact_page.dart`: in-app feedback and bug-report form with app diagnostics
- `lib/contact/submissions_csv_page.dart`: hosted-submission viewer used by the Information tab
- `lib/app/app_metadata.dart`: version constants surfaced in diagnostics and the Information tab
- `store_listing/`: Google Play listing copy
- `scripts/`: release build, version bump, docs audit, and cleanup helper scripts
- `tool/`: Android release build and dependency snapshot helpers
- `test/`: unit and widget tests for gameplay, persistence, and responsive layout
- `android/`, `ios/`, `web/`, `windows/`, `linux/`, `macos/`: platform targets
- `pubspec.yaml`: dependencies, Flutter package version, and MSIX configuration

## Version

| Target | Version |
| --- | --- |
| Flutter package (`pubspec.yaml`) | `0.1.54+55` |
| MSIX package (`msix_config.msix_version`) | `0.1.54.55` |
| Android package name | `com.stefanronnkvist.paid.squarenumber` |

The Information tab renders the AAB and MSIX versions from `lib/app/app_metadata.dart`. `scripts/bump-version.ps1` updates `pubspec.yaml`, `android/local.properties`, and `lib/app/app_metadata.dart` together, so run it instead of editing version numbers by hand.

## Documentation Audit

`scripts/audit-docs.ps1` verifies that the shipped documentation still matches the app:

- `pubspec.yaml`, `lib/app/app_metadata.dart`, and the MSIX version agree
- README's version table and the Information tab test use the current version
- The store listing stays within Google Play's 80-character short and 4000-character long limits
- The Help tab still documents the rules the game enforces
- Every relative link in README resolves to a real file

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/audit-docs.ps1
```

It exits non-zero with a list of problems, and runs as part of the `Google Store` VS Code task before any release build. Run `scripts/bump-version.ps1` first when releasing; it updates every version source together.

## License

No license file is currently included. Add a `LICENSE` file if you plan to distribute publicly.
