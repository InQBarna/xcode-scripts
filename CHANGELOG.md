# Changelog

## 2.0.0 (unreleased)

Breaking: generated projects are now SPM-only, and the repo moved to GitHub.

- All URLs moved from the retired gitlab.inqbarna.com to https://github.com/InQBarna/xcode-scripts (HTTPS).
- Generated Fastfile imports `CommonFastfile` with `version: '~> 2.0'`. Releases are git tags.
- Removed CocoaPods: no `pod init`/`pod install`, no Podfile/workspace lookup; build uses `-project`. 
- Ruby 3.3.7, Homebrew prefix detected (Apple Silicon), bash shebangs, `exit 1` instead of `exit -1`.
- `build.sh`: simulator runtime and device default to the newest installed ones (override with `RUNTIME`, `DEVICE`).
- `CommonFastfile`: removed `compileBitcode`, `fastlane_version` raised to 2.220.0.
- Build/test logic moved from the generated `build.sh` into shared lanes: `iq_build` / `iq_test` helpers in `CommonFastfile`, `build` and `test` lanes in the generated Fastfile. `build.sh` is now a thin wrapper. Warnings from Swift packages no longer count. Fixed `build.sh` bugs (inverted `JOB_NAME` check, UI tests run against a non-existent target).
- Generated `.gitignore` also ignores build/test artifacts and `fastlane/AuthKey_*.p8` / `fastlane/.env*`; this repo got a `.gitignore`.
- CI templates in `templates/` (GitHub Actions `ci.yml` and `distribute.yml`, `Jenkinsfile`), offered by the generator (`CI_PROVIDER`).
- New `iq_asc_api_key` helper: App Store Connect key from `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_P8` env vars (CI secrets) or a key file. The generated Fastfile only configures it for lanes other than `build` / `test`.
- `slather` and `xchtmlreport` removed. `iq_test` reads the xcresult with fastlane's `trainer` (junit) and `xccov` (coverage, converted to `coverage/cobertura.xml` by `iq_cobertura_from_xcresult`). Results are now written even when tests fail. The Gemfile only has `fastlane` and `xcodeproj`.
- `xcinstall/install.sh` rewritten on top of `xcodes` (`xcode-install` / `xcversion` are deprecated, `xcinstall/Gemfile` removed). `.xcode-version` (created by the generator) selects the Xcode in `build.sh` and the GitHub Actions workflow.
- `setup_match.sh`: fixed inverted check that tried to re-import the common Fastfile when already present.

## 1.x

See git history (`renew_certs` lane added Nov 2026).
