# xcode-scripts

Common tooling to start a **new iOS project ready for CI/CD** (Swift Package Manager only).
It generates the scripts and fastlane setup so every project builds, tests and ships the same way.

## What you get

- `scripts/setup.sh`: installs what a machine needs (rbenv, Ruby, bundler, gems). Idempotent.
- `scripts/build.sh`: builds the project with **0 warnings allowed**; with `INTENT=test` also runs unit/UI tests and reports coverage.
- `fastlane/Fastfile` importing the shared lanes from this repo (`fastlane/CommonFastfile`), pinned to a major version.
- Build number build phase (`YYYYMMddHHmm`), match setup, `.gitignore`.

### Shared lanes (`fastlane/CommonFastfile`)

| Lane | What it does |
|---|---|
| `update_devices_and_profiles` | Registers `fastlane/devices.txt` on the dev portal and regenerates development/adhoc/appstore profiles with match |
| `install_profiles` | Installs existing profiles read-only (no dev portal access needed) |
| `renew_certs` | Renews expired certificates and regenerates profiles. `dry_run:true` only lists what would be deleted |

Helper methods used from your project's lanes: `iq_beta` (TestFlight) and `iq_firebase_v2` (Firebase App Distribution).
Both build, upload, upload dSYMs to Crashlytics, bump the version, and push a git tag.

## Versioning

Generated Fastfiles import this repo with `version: '~> 2.0'`, so projects only receive compatible changes.
Releases are git tags (`v2.x.y`); see [CHANGELOG.md](CHANGELOG.md). To pick up a new major version, bump the version in your Fastfile.

## Set up a new project

1. Grab the requirements (seriously, grab them first):
    - Repository created on GitHub
    - App name
    - Bundle identifier created on the dev portal
    - Apple team id
    - Match git repo url
    - Firebase app id (looks like `1:XXXX:ios:XXXX`), if using Firebase distribution
    - App Store Connect API key: key id, issuer id and the `.p8` file
    - App created on App Store Connect

2. Clone your project repository and create the Xcode project at its root (iOS app, existing bundle id). Close Xcode.

3. From the project root, run the generator (it asks for some input, so use process substitution, not `curl | bash`):
```
bash <(curl -fsSL https://raw.githubusercontent.com/InQBarna/xcode-scripts/master/create_setup_build_scripts.sh)
```
   or, with this repo cloned next to your project: `../xcode-scripts/create_setup_build_scripts.sh`.
   Use `XCODE_SCRIPTS_REF=<branch|tag>` to test another version of the helper scripts.

4. Finish the manual bits:
    - Put the Firebase id in `fastlane/Fastfile`
    - Download the `.p8` file to `fastlane/` and set key id and issuer id in `fastlane/Fastfile`
    - Make sure the scheme is **shared** (Product > Scheme > Manage Schemes) and committed
    - Scheme > Test: enable "Gather coverage" for **all targets**

5. Verify: `./scripts/setup.sh` and then `./scripts/build.sh` (`INTENT=test ./scripts/build.sh` to run tests).

   Simulator defaults to the newest installed iOS runtime and iPhone; override with `RUNTIME=18.2 DEVICE="iPhone 16"`.
   Xcode other than `/Applications/Xcode.app`: `XCODE_EXTRA_PATH=-16.2` (uses `/Applications/Xcode-16.2.app`).

## App Store / TestFlight

- (Optional) Write devices to `fastlane/devices.txt`, or download them with
  `bundle exec ruby ../xcode-scripts/samples/read_devices_from_developer_portal.rb` (needs username/password credentials, not API keys).
- Create the profiles: `bundle exec fastlane update_devices_and_profiles`
- (Optional) Unset "Automatically manage signing" and select the new profiles for each configuration.
- Ship: `bundle exec fastlane beta`

## Firebase App Distribution (optional)

- Add Firebase with SPM following console.firebase.com (add `GoogleService-Info.plist`, etc.).
  If Crashlytics symbol upload fails with SPM, set `UPLOAD_SYMBOLS_PATH` (see the commented example in `scripts/build.sh`).
- Enable beta distribution on the Firebase website.
- Add the plugin: `bundle exec fastlane add_plugin firebase_app_distribution`
- Locally, be logged in with `firebase login`.
- Ship: `bundle exec fastlane firebase`

## Other usual setup (`samples/`)

| Script | Purpose |
|---|---|
| `add_adhoc_config.rb` | Adds an AdHoc config copying Release (then select profiles and point `iq_firebase_v2` to `adhoc`) |
| `add_appstore_config.rb` | Adds an AppStore config |
| `add_swiftlint_build_phase.rb` / `add_swiftformat_build_phase.rb` | Adds the lint/format build phase |
| `add_bundleversion_build_phase.rb` | Build number build phase (done by the generator) |
| `add_settings_bundle.rb`, `add_fluent.rb` | Settings bundle / Fluent localization |
| `read_devices_from_developer_portal.rb` | Downloads registered devices into `fastlane/devices.txt` |

Run them with `bundle exec ruby ../xcode-scripts/samples/<script>`.

## Xcode installation on CI machines

`xcinstall/install.sh <version>` installs and selects an Xcode version (needs `XCODE_INSTALL_USER` / `XCODE_INSTALL_PASSWORD`).

## Roadmap

- GitHub Actions and Jenkins templates calling the same lanes
- Build/test logic moved into shared lanes, `build.sh` as a thin wrapper
- Replace `xcode-install` with `xcodes`; replace `slather`/`xchtmlreport` with native coverage and result bundle tooling
- Non-interactive generator (env vars), `doctor` check script, rename `beta` lane to `testflight`
