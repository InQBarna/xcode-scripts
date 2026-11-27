#!/bin/bash
# End-to-end smoke test: generates a throwaway iOS project, runs the generator on it and checks that
# the generated scripts and lanes work (build with 0 warnings, unit + UI tests, junit, coverage).
#
#   tests/smoke.sh                 run everything (needs macOS, Xcode with an iOS simulator runtime, brew, network)
#   SMOKE_KEEP=1 tests/smoke.sh    keep the temporary project (path printed) for debugging
#
# Note: scripts/setup.sh, run by the generator, installs rbenv + the pinned Ruby when missing.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
FAILED=0

pass() { echo "  ok   $1"; }
fail() { echo "  FAIL $1"; FAILED=1; }
check() { # check "description" command...
    local description="$1"; shift
    if "$@" > /dev/null 2>&1; then pass "$description"; else fail "$description"; fi
}
step() { echo; echo "== $1"; }
cleanup() {
    if [[ -n "$SMOKE_KEEP" ]]; then echo "Project kept at $WORK"; else rm -rf "$WORK"; fi
}
trap cleanup EXIT
die() { echo "ABORT: $1"; exit 1; }

step "Preparing sample project"
which xcodegen > /dev/null || brew install xcodegen || die "xcodegen is needed (brew install xcodegen)"
cp -R "$REPO/tests/fixtures/SampleApp" "$WORK/SampleApp"
cd "$WORK/SampleApp" || die "cannot enter $WORK"
xcodegen generate > /dev/null || die "xcodegen failed"
git init -q && git add -A && git -c user.name=smoke -c user.email=smoke@example.com commit -q -m "sample project" || die "git setup failed"

step "Running the generator"
TEAM_ID=ABCDE12345 MATCH_GIT_URL=https://example.invalid/match.git CI_PROVIDER=both XCODE_SCRIPTS_USE_LOCAL=1 \
    "$REPO/create_setup_build_scripts.sh" > "$WORK/generator.log" 2>&1 || { tail -30 "$WORK/generator.log"; die "generator failed (log: $WORK/generator.log)"; }
for f in Gemfile scripts/setup.sh scripts/build.sh fastlane/Fastfile fastlane/Appfile fastlane/Matchfile fastlane/devices.txt \
         .gitignore .xcode-version .ruby-version Jenkinsfile .github/workflows/ci.yml .github/workflows/distribute.yml; do
    check "generated $f" test -f "$f"
done
check "Gemfile has no cocoapods" bash -c '! grep -qi cocoapods Gemfile'
check "Fastfile has the build/test lanes filled in" bash -c 'grep -q "xcprojname: \"SampleApp\"" fastlane/Fastfile && grep -q "test_target: \"SampleAppTests\"" fastlane/Fastfile && grep -q "ui_test_target: \"SampleAppUITests\"" fastlane/Fastfile'
check "Fastfile imports CommonFastfile once" bash -c '[ "$(grep -c CommonFastfile fastlane/Fastfile)" = "1" ]'
check "Matchfile has the team and repo" bash -c 'grep -q ABCDE12345 fastlane/Matchfile && grep -q example.invalid fastlane/Matchfile'
check "build number build phase added" grep -q "BUILD NUMBER FROM FASTLANE TO PLIST" SampleApp.xcodeproj/project.pbxproj
git add -A && git -c user.name=smoke -c user.email=smoke@example.com commit -q -m "generated" || die "git commit failed"

step "scripts/build.sh (build only)"
if ./scripts/build.sh > "$WORK/build.log" 2>&1; then pass "build succeeds"; else fail "build succeeds"; tail -30 "$WORK/build.log"; fi
check "deriveddata cleaned up" test ! -d deriveddata

step "INTENT=test scripts/build.sh (build + unit tests + UI tests)"
if INTENT=test ./scripts/build.sh > "$WORK/test.log" 2>&1; then pass "test run succeeds"; else fail "test run succeeds"; tail -40 "$WORK/test.log"; fi
check "unit tests junit has the test" grep -q "testAdd" fastlane/test_output/report.junit
check "UI tests junit has the test" grep -q "testLaunch" fastlane/test_output_ui/report.junit
check "cobertura exists" test -s coverage/cobertura.xml
check "cobertura covers Calculator.swift" grep -q "Calculator.swift" coverage/cobertura.xml
check "cobertura ignores the tests" bash -c '! grep -q "CalculatorTests.swift" coverage/cobertura.xml'
check "coverage is partial (subtract is not tested)" bash -c 'grep -o "line-rate=\"[0-9.]*\"" coverage/cobertura.xml | head -1 | grep -qv "line-rate=\"1.0000\""'

step "A warning must fail the build"
cat > SampleApp/Warning.swift <<'SW'
func warns() {
    var neverMutated = 1
    print(neverMutated)
}
SW
xcodegen generate > /dev/null || die "xcodegen failed"   # the new file has to be part of the project
if ./scripts/build.sh > "$WORK/warning.log" 2>&1; then fail "build with a warning fails"; else pass "build with a warning fails"; fi
check "log mentions the warnings" grep -q "warnings, invalid build" "$WORK/warning.log"
if MAX_WARNINGS=5 ./scripts/build.sh > "$WORK/warning2.log" 2>&1; then pass "MAX_WARNINGS=5 allows it"; else fail "MAX_WARNINGS=5 allows it"; tail -20 "$WORK/warning2.log"; fi
rm SampleApp/Warning.swift

step "A failing test must still write the reports and fail"
cat > SampleAppTests/FailingTests.swift <<'SW'
import XCTest
final class FailingTests: XCTestCase {
    func testFailsOnPurpose() { XCTFail("on purpose") }
}
SW
xcodegen generate > /dev/null || die "xcodegen failed"
if INTENT=test ./scripts/build.sh > "$WORK/failing.log" 2>&1; then fail "failing test fails the lane"; else pass "failing test fails the lane"; fi
check "junit reports the failure" grep -q "testFailsOnPurpose" fastlane/test_output/report.junit
rm SampleAppTests/FailingTests.swift

echo
if [[ $FAILED -eq 0 ]]; then echo "SMOKE TEST PASSED"; else echo "SMOKE TEST FAILED (logs in $WORK, run with SMOKE_KEEP=1 to keep them)"; fi
exit $FAILED
