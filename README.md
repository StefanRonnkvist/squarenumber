# Square Number

Square Number is a falling-number puzzle game built with Flutter. Guide each active square into a match, chain clears as the board settles, and keep the five-column stack below the top border. The repository includes release build tasks for Android, web, and Windows, plus Flutter platform targets for iOS, Linux, and macOS.

## Gameplay

1. Select **Start**, then drag the active falling square sideways or down. Releasing it snaps it to one of five columns; it continues falling until it lands, and landed squares cannot be moved.
2. Clear at least two equal squares that touch at an edge or corner, or clear an orthogonally connected chain of at least three unique values where each neighboring value differs by exactly one. Consecutive chains can turn corners, but a repeated value inside a chain (for example `1-2-1`) does not count.
3. For each matching group in a clear, calculate `(sum of values) x (number of squares in that group)`. Add those group scores together, then apply the current cascade multiplier.
4. When a clear removes support, falling squares can settle into another clear. The multiplier starts at x1, increases after each clear in the cascade, and resets when the next square appears. Floating score indicators show the points earned by each clear.
5. The effective speed starts at your chosen base speed, increases by `0.10x` every 500 points, and is capped at `1.50x`.
6. The run ends when a placed square extends above the top border.

## Controls And Saved Runs

- **Start/Pause** starts or pauses the current board. On narrow screens these commands use icon buttons with tooltips.
- **New Game** records a positive current score as a completed run, clears the board, and immediately starts a new run. Game over also completes the run; the **Restart** control begins a fresh run.
- Moving the app to the background pauses the game and saves a non-empty board. The saved board and score are restored in a paused state on the next launch.
- Switching away from the game on a phone pauses an active run. Phone gameplay uses portrait orientation; changing orientation or resizing the board pauses a running game.
- Changing either generated-number bound starts a fresh board. Base speed and theme changes apply directly.
- Tablet and desktop layouts support portrait and landscape orientations.
- The current positive score appears in Score History only when it qualifies for the top 10. It is marked **Current** while in progress; completed entries retain their effective speed and Phone, Tablet, or Desktop layout label. **Clear History** removes completed-run history but does not clear the separately saved highest score.

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
- Settings tabs for Controls, Score History, Information, and Help
- In-app feedback and bug-report form with app, platform, orientation, and layout diagnostics
- Hosted-submission viewer in the Information tab
- Built-in How to Play reference in the Help tab

Game state and score data use local preferences and do not require an account. The Information tab connects to the configured support host when sending feedback or loading hosted submissions.

## Store Listing

Google Play copy is maintained in [`store_listing/`](store_listing/):

- [`store_listing/google_play_short_synopsis.txt`](store_listing/google_play_short_synopsis.txt) — the short description used on the store listing.
- [`store_listing/google_play_long_synopsis.txt`](store_listing/google_play_long_synopsis.txt) — the full description, kept within the 4000-character Google Play limit.

`assets/play_store_512.png` is bundled as a Flutter asset. The short and long copy target Google Play's 80-character and 4000-character limits respectively.

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
| Flutter package (`pubspec.yaml`) | `0.1.64+65` |
| MSIX package (`msix_config.msix_version`) | `0.1.64.65` |
| Android package name | `com.stefanronnkvist.paid.squarenumber` |

`scripts/bump-version.ps1` updates `pubspec.yaml` and `android/local.properties`; it does not update `lib/app/app_metadata.dart` or this README. The app metadata currently reports `0.1.56+57` (`0.1.56.57` for MSIX), so its displayed diagnostic versions are out of step with the package versions above.

## Documentation Maintenance

Keep this README, the Help tab in `lib/features/settings/widgets/settings_tab.dart`, and the Google Play copy in `store_listing/` aligned with the rules and settings implemented by the game. Google Play limits the short and long descriptions to 80 and 4000 characters respectively. The current `scripts/audit-docs.ps1` still refers to files from a different, legacy project and is not a valid audit for Square Number.

### Release flow

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/bump-version.ps1
```

The version script updates `pubspec.yaml` and `android/local.properties`. Before release, manually verify the README version table, `lib/app/app_metadata.dart`, and the Google Play descriptions; the current documentation audit script targets a legacy project and must not be used as a Square Number release gate.

## License

No license file is currently included. Add a `LICENSE` file if you plan to distribute publicly.
