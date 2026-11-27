#!/bin/bash
# Fast tests (no Xcode, no Apple account) of the lanes in fastlane/CommonFastfile that talk to the developer
# portal or to lint tools: Spaceship and the tools are stubbed, the lane plumbing is real.
# Needs ruby + bundler + network (installs fastlane in a temporary project).
#
#   tests/lanes.sh

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
FAILED=0
trap 'rm -rf "$WORK"' EXIT

pass() { echo "  ok   $1"; }
fail() { echo "  FAIL $1"; FAILED=1; }
step() { echo; echo "== $1"; }

mkdir -p "$WORK/fastlane" "$WORK/bin" && cd "$WORK" || exit 1
cat > Gemfile <<'GEM'
source "https://rubygems.org"
gem 'fastlane'
GEM
cat > fastlane/Matchfile <<'MF'
git_url("https://example.invalid/match.git")
type("development")
app_identifier ["com.example.app"]
MF
cat > fastlane/Fastfile <<RB
import '$REPO/fastlane/CommonFastfile'
require 'spaceship'

# --- stubs: no Apple account needed ---
def iq_connect_token; end
FakeCert = Struct.new(:display_name, :name, :certificate_type, :expiration_date)
FakeProfile = Struct.new(:name, :expiration_date, :profile_state)
FakeDevice = Struct.new(:udid, :name, :platform, :status)
def fake_portal(certs: [], profiles: [], devices: [])
  Spaceship::ConnectAPI::Certificate.define_singleton_method(:all) { |**| certs }
  Spaceship::ConnectAPI::Profile.define_singleton_method(:all) { |**| profiles }
  Spaceship::ConnectAPI::Device.define_singleton_method(:all) { |**| devices }
end
def days(n) (Time.now + n * 86_400).utc.iso8601 end

platform :ios do
  lane :t_expiry do
    now = Time.utc(2026, 1, 1)
    UI.user_error!('ok') unless iq_expiry_status(Time.utc(2026, 6, 1), now: now)[0] == :ok
    UI.user_error!('expiring') unless iq_expiry_status('2026-01-20T00:00:00.000+0000', warn_days: 30, now: now) == [:expiring, 19]
    UI.user_error!('expired') unless iq_expiry_status('2025-12-30T00:00:00.000+0000', now: now)[0] == :expired
  end

  lane :t_certs_healthy do |o|
    fake_portal(certs: [FakeCert.new('Apple Distribution', nil, 'IOS_DISTRIBUTION', days(200))],
                profiles: [FakeProfile.new('match AppStore com.example.app', days(200), 'ACTIVE'),
                           FakeProfile.new('someone elses profile', days(-5), 'INVALID')])
    rows = iq_check_certs(warn_days: 30, strict: true)
    UI.user_error!("unrelated profile was listed: #{rows.map { |r| r[:name] }}") unless rows.count == 2
  end
  lane :t_certs_expiring do |o|
    fake_portal(certs: [FakeCert.new('Apple Distribution', nil, 'IOS_DISTRIBUTION', days(10))],
                profiles: [FakeProfile.new('match AppStore com.example.app', days(200), 'ACTIVE')])
    iq_check_certs(warn_days: 30, strict: iq_true?(o[:strict]))
  end
  lane :t_certs_invalid do
    fake_portal(certs: [], profiles: [FakeProfile.new('match AdHoc com.example.app 1732', days(200), 'INVALID')])
    iq_check_certs(warn_days: 30, strict: true)
  end

  lane :t_devices do |o|
    fake_portal(devices: [FakeDevice.new('B-2', "Zed  iPhone", 'IOS', 'ENABLED'),
                          FakeDevice.new('A-1', 'Alice iPad', 'IOS', 'ENABLED'),
                          FakeDevice.new('C-3', 'Old phone', 'IOS', 'DISABLED'),
                          FakeDevice.new('D-4', 'A Mac', 'MAC_OS', 'ENABLED')])
    iq_sync_devices(dry_run: iq_true?(o[:dry_run]))
  end

  lane :t_next_version do
    {
      ['1.0', 'minor'] => '1.1', ['1.0', 'patch'] => '1.0.1', ['1.0', 'major'] => '2.0',
      ['1.2.3', 'patch'] => '1.2.4', ['1.2.3', 'minor'] => '1.3.0', ['1.2.3', 'major'] => '2.0.0',
      ['1', 'major'] => '2.0', ['9.9.9', 'patch'] => '9.9.10'
    }.each do |(current, bump), expected|
      got = iq_next_version(current, bump)
      UI.user_error!("#{current} #{bump}: expected #{expected}, got #{got}") unless got == expected
    end
  end

  # edits a real (tiny) project with the xcodeproj gem, both per-target and project-level MARKETING_VERSION
  lane :t_marketing_version do
    require 'xcodeproj'
    path = File.join(iq_root, 'Tiny.xcodeproj')
    FileUtils.rm_rf(path)
    project = Xcodeproj::Project.new(path)
    target = project.new_target(:application, 'Tiny', :ios, '17.0')
    target.build_configurations.each { |c| c.build_settings['MARKETING_VERSION'] = '1.0' }
    project.build_configurations.each { |c| c.build_settings['MARKETING_VERSION'] = '1.0' }
    project.save
    before, after = iq_set_marketing_version(path, 'Tiny', bump: 'minor')
    UI.user_error!("#{before} -> #{after}") unless [before, after] == ['1.0', '1.1']
    iq_set_marketing_version(path, 'Tiny', version: '3.4.5')
    reopened = Xcodeproj::Project.open(path)
    values = (reopened.targets.first.build_configurations + reopened.build_configurations).map { |c| c.build_settings['MARKETING_VERSION'] }.uniq
    UI.user_error!("not all configurations updated: #{values}") unless values == ['3.4.5']
    bare_path = File.join(iq_root, 'Bare.xcodeproj')
    bare = Xcodeproj::Project.new(bare_path)
    bare.new_target(:application, 'Bare', :ios, '17.0')
    bare.save
    UI.user_error!('should return nil without MARKETING_VERSION') unless iq_set_marketing_version(bare_path, 'Bare', bump: 'patch').nil?
  end

  lane :t_bump_args do
    [{}, { bump: 'huge' }, { version: 'x' }, { bump: 'patch', version: '1.0' }].each do |args|
      begin
        iq_bump_version(xcprojname: 'None', targetname: 'None', **args)
        UI.user_error!("accepted #{args}")
      rescue FastlaneCore::Interface::FastlaneError => e
        raise if e.message.start_with?('accepted')
      end
    end
  end

  lane :t_lint do |o|
    iq_lint(strict: iq_true?(o[:strict]) || o[:strict].nil?)
  end
end
RB
echo "[lanes.sh] installing fastlane in a temporary project"
bundle install --quiet > "$WORK/bundle.log" 2>&1 || { cat "$WORK/bundle.log"; echo "bundle install failed"; exit 1; }

run() { bundle exec fastlane ios "$@" > "$WORK/out.log" 2>&1; }
ok_lane()   { if run "$@"; then pass "$*"; else fail "$* (should pass)"; tail -15 "$WORK/out.log"; fi; }
fails_lane() { if run "$@"; then fail "$* (should fail)"; else pass "$* fails as expected"; fi; }
out_has() { if grep -q "$1" "$WORK/out.log"; then pass "output: $1"; else fail "output should contain: $1"; tail -15 "$WORK/out.log"; fi; }

step "expiry classification"
ok_lane t_expiry

step "check_certs"
ok_lane t_certs_healthy
out_has "Nothing expires in the next 30 days"
ok_lane t_certs_expiring strict:false
out_has "renew_certs"
fails_lane t_certs_expiring strict:true
out_has "Certificates need renewal"
fails_lane t_certs_invalid
out_has "INVALID"

step "sync_devices"
ok_lane t_devices dry_run:true
[[ ! -f fastlane/devices.txt ]] && pass "dry_run writes nothing" || fail "dry_run wrote the file"
ok_lane t_devices
EXPECTED=$'Device ID\tDevice Name\nA-1\tAlice iPad\nB-2\tZed iPhone\n'
[[ "$(cat fastlane/devices.txt)" == "${EXPECTED%$'\n'}" ]] && pass "devices.txt: enabled iOS devices only, sorted, names cleaned" || { fail "devices.txt content"; cat -A fastlane/devices.txt; }
ok_lane t_devices
out_has "already up to date"

step "bump_version"
ok_lane t_next_version
ok_lane t_marketing_version
ok_lane t_bump_args

step "lint"
# A PATH where the real swiftlint/swiftformat (if installed on this machine) are not visible
hide_tools() {
    local newpath="" d f b farm dirs
    IFS=: read -ra dirs <<< "$PATH"
    for d in "${dirs[@]}"; do
        if [[ -x "$d/swiftlint" || -x "$d/swiftformat" ]]; then
            farm="$WORK/farm$RANDOM"; mkdir -p "$farm"
            for f in "$d"/*; do b=$(basename "$f"); [[ "$b" == swiftlint || "$b" == swiftformat ]] || ln -s "$f" "$farm/$b"; done
            d="$farm"
        fi
        newpath="$newpath:$d"
    done
    echo "${newpath#:}"
}
CLEAN_PATH="$(hide_tools)"
export PATH="$CLEAN_PATH"
ok_lane t_lint
out_has "Nothing to lint"
touch .swiftlint.yml
fails_lane t_lint
out_has "configured but not installed"
printf '#!/bin/bash\necho "swiftlint $@"; exit 0\n' > bin/swiftlint; chmod +x bin/swiftlint
PATH="$WORK/bin:$CLEAN_PATH" ok_lane t_lint
out_has "swiftlint lint --strict"
PATH="$WORK/bin:$CLEAN_PATH" ok_lane t_lint strict:false
out_has "swiftlint lint --quiet"
printf '#!/bin/bash\necho "violations"; exit 2\n' > bin/swiftlint
PATH="$WORK/bin:$CLEAN_PATH" fails_lane t_lint
out_has "swiftlint found problems"
touch .swiftformat
printf '#!/bin/bash\nexit 0\n' > bin/swiftlint
PATH="$WORK/bin:$CLEAN_PATH" fails_lane t_lint
out_has "swiftformat is configured but not installed"

echo
if [[ $FAILED -eq 0 ]]; then echo "LANES TEST PASSED"; else echo "LANES TEST FAILED"; fi
exit $FAILED
