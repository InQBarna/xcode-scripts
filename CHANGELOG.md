# Changelog

## 2.0.0 (unreleased)

Breaking: generated projects are now SPM-only, and the repo moved to GitHub.

- All URLs moved from the retired gitlab.inqbarna.com to https://github.com/InQBarna/xcode-scripts (HTTPS).
- Generated Fastfile imports `CommonFastfile` with `version: '~> 2.0'`. Releases are git tags.
- Removed CocoaPods: no `pod init`/`pod install`, no Podfile/workspace lookup; build uses `-project`. 
- Homebrew prefix detected (Apple Silicon), bash shebangs, `exit 1` instead of `exit -1`.
- `build.sh`: simulator runtime and device default to the newest installed ones (override with `RUNTIME`, `DEVICE`).
- `CommonFastfile`: removed `compileBitcode`, `fastlane_version` raised to 2.220.0.
- Build/test logic moved from the generated `build.sh` into shared lanes: `iq_build` / `iq_test` helpers in `CommonFastfile`, `build` and `test` lanes in the generated Fastfile. `build.sh` is now a thin wrapper. Warnings from Swift packages no longer count. Fixed `build.sh` bugs (inverted `JOB_NAME` check, UI tests run against a non-existent target).
- Generated `.gitignore` also ignores build/test artifacts and `fastlane/AuthKey_*.p8` / `fastlane/.env*`; this repo got a `.gitignore`.
- CI templates in `templates/` (GitHub Actions `ci.yml` and `distribute.yml`, `Jenkinsfile`), offered by the generator (`CI_PROVIDER`).
- New `iq_asc_api_key` helper: App Store Connect key from `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_P8` env vars (CI secrets) or a key file. The generated Fastfile only configures it for lanes other than `build` / `test`.
- `slather` and `xchtmlreport` removed. `iq_test` reads the xcresult with fastlane's `trainer` (junit) and `xccov` (coverage, converted to `coverage/cobertura.xml` by `iq_cobertura_from_xcresult`). Results are now written even when tests fail. The Gemfile only has `fastlane` and `xcodeproj`.
- `xcinstall/install.sh` rewritten on top of `xcodes` (`xcode-install` / `xcversion` are deprecated, `xcinstall/Gemfile` removed). `.xcode-version` (created by the generator) selects the Xcode in `build.sh` and the GitHub Actions workflow.
- TestFlight: helper renamed `iq_beta` -> `iq_testflight` and generated lane `beta` -> `ship_testflight` (a lane called `testflight` clashes with fastlane's action of the same name). `iq_beta` stays as a deprecated alias that warns, so existing `lane :beta` keep working. `INTENT=testflight` in `build.sh` / Jenkinsfile (`INTENT=appstore` still accepted by `build.sh`). Git tags stay `appstore/v...`.
- Generator can run unattended (`TEAM_ID`, `MATCH_GIT_URL`, `CI_PROVIDER`) and from a clone (`XCODE_SCRIPTS_USE_LOCAL=1`); helper scripts are no longer written to fixed `/tmp` paths.
- `tests/smoke.sh` + `tests/fixtures/SampleApp`: end-to-end test of the generator and the generated build/test setup, run by `.github/workflows/ci.yml` together with syntax checks. It found and fixed two bugs: `build.sh` rejected any bundler other than 2.x, and building for testing through `gym` silently dropped the test bundles (it appends its own `build` action), so unit tests could not run; `scan(build_for_testing: true)` is used instead.
- No versions are pinned in this repo any more (an earlier draft hardcoded the Ruby of the author's machine). The generator picks the latest stable Ruby known to ruby-build (`XCODE_SCRIPTS_RUBY=x.y.z` overrides) and writes it to the project's `.ruby-version`; `setup.sh`, `build.sh` and the Gemfile (`ruby file: '.ruby-version'`) read it from there. Bundler is the one shipped with that Ruby, Gemfile.lock records it. CI templates use `macos-latest`; generated projects get a `dependabot.yml` for actions and gems. Verified with Ruby 4.0.10, bundler 4.0.20, fastlane 2.242.0.
- `scripts/doctor.sh` (from `templates/doctor.sh`) checks Xcode, simulator, Ruby, gems, shared scheme and coverage, fastlane files, signing and CI, a committed `.p8` key, and prints a fix for each problem (`--offline` skips network checks).
- Weekly CI run of the smoke test against the newest versions, plus `tests/check-actions.sh` for outdated actions in the templates; a failure opens (or comments on) a `versions` issue.
- `setup_match.sh`: fixed inverted check that tried to re-import the common Fastfile when already present.

## 1.x

See git history (`renew_certs` lane added Nov 2026).
