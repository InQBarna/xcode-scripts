# Changelog

## 2.0.0 (unreleased)

Breaking: generated projects are now SPM-only, and the repo moved to GitHub.

- All URLs moved from the retired gitlab.inqbarna.com to https://github.com/InQBarna/xcode-scripts (HTTPS).
- Generated Fastfile imports `CommonFastfile` with `version: '~> 2.0'`. Releases are git tags.
- Removed CocoaPods: no `pod init`/`pod install`, no Podfile/workspace lookup; build uses `-project`. `slather` kept for coverage.
- Ruby 3.3.7, Homebrew prefix detected (Apple Silicon), bash shebangs, `exit 1` instead of `exit -1`.
- `build.sh`: simulator runtime and device default to the newest installed ones (override with `RUNTIME`, `DEVICE`).
- `CommonFastfile`: removed `compileBitcode`, `fastlane_version` raised to 2.220.0.
- `setup_match.sh`: fixed inverted check that tried to re-import the common Fastfile when already present.

## 1.x

See git history (`renew_certs` lane added Nov 2026).
