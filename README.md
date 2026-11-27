# xcode-scripts

Common tooling to start a **new iOS project ready for CI/CD** (Swift Package Manager only).
It generates the scripts and fastlane setup so every project builds, tests and ships the same way.

## What you get

- `scripts/setup.sh`: installs what a machine needs (rbenv, the Ruby from `.ruby-version`, gems). Idempotent.
- `scripts/doctor.sh`: checks the whole setup (Xcode, Ruby, gems, scheme, fastlane, signing, CI) and says how to fix what is wrong.
- `scripts/build.sh`: builds the project with **0 warnings allowed**; with `INTENT=test` also runs unit/UI tests and reports coverage.
- `fastlane/Fastfile` importing the shared lanes from this repo (`fastlane/CommonFastfile`), pinned to a major version.
- Build number build phase (`YYYYMMddHHmm`), match setup, `.gitignore`.

### Shared lanes (`fastlane/CommonFastfile`)

| Lane | What it does |
|---|---|
| `update_devices_and_profiles` | Registers `fastlane/devices.txt` on the dev portal and regenerates development/adhoc/appstore profiles with match |
| `install_profiles` | Installs existing profiles read-only (no dev portal access needed) |
| `renew_certs` | Renews expired certificates and regenerates profiles. `dry_run:true` only lists what would be deleted |
| `check_certs` | Lists certificates and match profiles with their expiry (`warn_days:30`). `strict:true` fails when something is expired, expiring or invalid: run it weekly on CI so renewal is never a surprise. Read only, needs just the API key |
| `sync_devices` | Writes the enabled iOS devices of the developer portal to `fastlane/devices.txt` and shows what changed (`dry_run:true` to only look). Uses the API key, so no username/password needed |
| `lint` | Runs SwiftLint (`--strict`, `strict:false` to allow warnings) and SwiftFormat (`--lint`, nothing is modified) when configured/installed. Fails if a tool has a config file but is not installed |
| `bump_version` | Generated in your Fastfile: `bump_version bump:patch\|minor\|major` or `bump_version version:1.2.3`; changes the marketing version and commits it |

Helper methods called from the lanes of your project's Fastfile (the generator creates them):

| Helper | Project lane | What it does |
|---|---|---|
| `iq_build` | `build` | Builds for the simulator, fails on warnings (warnings inside Swift packages are ignored) |
| `iq_test` | `test` | Build (0 warnings), unit tests with coverage (`coverage/cobertura.xml`), UI tests with junit report (`fastlane/test_output_ui/report.junit`) |
| `iq_testflight` | `ship_testflight` | Builds and uploads to TestFlight, uploads dSYMs, bumps the version, pushes a git tag |
| `iq_firebase_v2` | `firebase` | Same, for Firebase App Distribution (AdHoc) |

`scripts/build.sh` is just a wrapper: no `INTENT` runs `fastlane build`, `INTENT=test` runs `fastlane test`, `firebase`/`testflight` run the distribution lanes.
Tunable with env vars: `RUNTIME`, `DEVICE`, `MAX_WARNINGS` (default 0), `DO_NOT_DELETE_SIMULATOR`. When `BUILD_NUMBER` is set (Jenkins) a dedicated throw-away simulator is created per job.
UI tests are reported but don't fail the lane by default (`fail_on_ui_test_failure: true` in the `test` lane to change it); UI tests are skipped when the project has no UI test target.
Results are written even when tests fail (the lane fails at the end): junit with fastlane's `trainer`, coverage converted from the xcresult with `xccov` to `coverage/cobertura.xml` (Swift packages and test targets excluded; `coverage_ignore: [...]` in the `test` lane adds more). No extra gems or brew packages are needed.

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

## CI (GitHub Actions and Jenkins)

The generator asks which CI templates to add (`CI_PROVIDER=github|jenkins|both|none` to skip the question). Existing files are never overwritten.
Templates live in `templates/` and call the same lanes you run locally, so CI and your machine behave the same.

| File created | What it does |
|---|---|
| `.github/workflows/ci.yml` | On every PR and push to main: `fastlane test`, uploads coverage and junit results as artifacts |
| `.github/workflows/distribute.yml` | Manual run (Actions tab): sends a build to Firebase or TestFlight with `fastlane firebase` / `ship_testflight` |
| `Jenkinsfile` | `Setup` + `Build / test` (publishes junit and cobertura) + `Distribute`, chosen with the `INTENT` parameter |

Secrets for distribution (GitHub repository secrets / Jenkins credentials):

| Name | Content |
|---|---|
| `MATCH_PASSPHRASE` | Passphrase of the match repo |
| `MATCH_GIT_BASIC_AUTHORIZATION` | GitHub only: base64 of `user:token` with read access to the match repo |
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` | App Store Connect API key (content of the `.p8`, so the key is never committed) |
| `FIREBASE_TOKEN` | Firebase distribution only, from `firebase login:ci` |

The generated Fastfile calls `iq_asc_api_key` in `before_all`, which uses those `ASC_*` env vars when present and falls back to the key file for local runs. `build` and `test` never need the key.

## App Store / TestFlight

- (Optional) Write devices to `fastlane/devices.txt`, or download them with
  `bundle exec ruby ../xcode-scripts/samples/read_devices_from_developer_portal.rb` (needs username/password credentials, not API keys).
- Create the profiles: `bundle exec fastlane update_devices_and_profiles`
- (Optional) Unset "Automatically manage signing" and select the new profiles for each configuration.
- Ship: `bundle exec fastlane ship_testflight`

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

`xcinstall/install.sh [version]` installs (with [xcodes](https://github.com/XcodesOrg/xcodes)) and selects an Xcode version; without argument it uses `.xcode-version`.
Downloading needs an Apple ID (`XCODES_USERNAME` / `XCODES_PASSWORD`) and an interactive 2FA code the first time, so do it once by hand on the machine.

The generator creates `.xcode-version` with your current Xcode. `scripts/build.sh` and the GitHub Actions workflow use that version when it is installed (`/Applications/Xcode-<version>.app`, as xcodes names it, or `Xcode_<version>.app`); `XCODE_EXTRA_PATH` still overrides it.

## Versions

A new project gets a current, **tested** set of versions, and this repo keeps them current automatically:

- **Ruby**: `versions.env` holds the version the smoke test last passed with (today 4.0.10). The generator writes it to the project's `.ruby-version` (`XCODE_SCRIPTS_RUBY=x.y.z` to choose another). From then on the project owns it: update `.ruby-version` and run `./scripts/setup.sh`. `scripts/doctor.sh` warns when it is close to end of life.
- **Bundler / gems / fastlane**: bundler is the one that ships with that Ruby; `Gemfile.lock` (commit it) pins everything for the project. Dependabot (generated `.github/dependabot.yml`) proposes updates.
- **Xcode**: `.xcode-version`, created from the Xcode you generate with.
- **GitHub runners / actions**: `macos-latest`; action versions are kept fresh by the generated Dependabot config.
- **CommonFastfile**: the only thing versioned here, with git tags; projects import `~> 2.0`.

How `versions.env` stays current without anybody choosing versions: `.github/workflows/versions.yml` runs every Monday, tries the newest stable Ruby with the smoke test, and **opens a PR bumping `versions.env` if it passes** or **an issue if it fails**. It also opens an issue when an action used in `templates/` has a newer major (`tests/check-actions.sh`). (The repo setting "Allow GitHub Actions to create and approve pull requests" must be on.) Last verified together: Ruby 4.0.10, bundler 4.0.20, fastlane 2.242.0, Xcode 26.4.

## Developing this repo

`tests/lanes.sh` is a fast test (a minute, no Xcode, no Apple account) of the portal and lint lanes with stubbed Spaceship and lint tools.

`tests/smoke.sh` is an end-to-end test: it generates a throwaway iOS project (`tests/fixtures/SampleApp`, with XcodeGen), runs the generator on it unattended and checks the result:
generated files, `bump_version`, `scripts/build.sh`, unit + UI tests, junit, coverage, a warning failing the build, and a failing test still writing its report. It takes a few minutes and needs macOS, Xcode with an iOS simulator, brew and network. It also runs in GitHub Actions (`smoke.yml`) on PRs that touch the generator, lanes, templates, samples, tests or `versions.env`; `lint.yml` runs syntax checks on every PR.

```
tests/smoke.sh                  # SMOKE_KEEP=1 keeps the temporary project for debugging
```

To try your local changes on a real project, run the generator from your clone with `XCODE_SCRIPTS_USE_LOCAL=1` (uses the clone's samples, templates and `CommonFastfile`).
Unattended generator: `TEAM_ID=... MATCH_GIT_URL=... CI_PROVIDER=github|jenkins|both|none`.

## Roadmap

- `doctor` check script
