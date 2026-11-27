# Changelog

## 2.0.0 (unreleased)

Breaking: generated projects are now SPM-only, and the repo moved to GitHub.

- All URLs moved from the retired gitlab.inqbarna.com to https://github.com/InQBarna/xcode-scripts (HTTPS).
- Generated Fastfile imports `CommonFastfile` with `version: '~> 2.0'`. Releases are git tags.
- Removed CocoaPods: no `pod init`/`pod install`, no Podfile/workspace lookup; build uses `-project`. `slather` kept for coverage.
- Ruby 3.3.7, Homebrew prefix detected (Apple Silicon), bash shebangs, `exit 1` instead of `exit -1`.
- `build.sh`: simulator runtime and device default to the newest installed ones (override with `RUNTIME`, `DEVICE`).
- `CommonFastfile`: removed `compileBitcode`, `fastlane_version` raised to 2.220.0.
- Build/test logic moved from the generated `build.sh` into shared lanes: `iq_build` / `iq_test` helpers in `CommonFastfile`, `build` and `test` lanes in the generated Fastfile. `build.sh` is now a thin wrapper. Warnings from Swift packages no longer count. Fixed `build.sh` bugs (inverted `JOB_NAME` check, UI tests run against a non-existent target).
- Generated `.gitignore` also ignores build/test artifacts and `fastlane/AuthKey_*.p8` / `fastlane/.env*`; this repo got a `.gitignore`.
- `setup_match.sh`: fixed inverted check that tried to re-import the common Fastfile when already present.

## 1.x

See git history (`renew_certs` lane added Nov 2026).
