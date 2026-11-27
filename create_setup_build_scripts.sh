#!/bin/bash
# Generates scripts/setup.sh, scripts/build.sh and a fastlane setup for a new (SPM-only) iOS project.
# Run it from the root of the project repository (where the .xcodeproj lives).
#
# Non interactive use (everything else is detected from the project):
#   TEAM_ID=XXXXXXXXXX MATCH_GIT_URL=<match repo url> CI_PROVIDER=github|jenkins|both|none ./create_setup_build_scripts.sh
# Testing changes of this repo from a clone: XCODE_SCRIPTS_USE_LOCAL=1 ../xcode-scripts/create_setup_build_scripts.sh
#   (uses the samples/templates of the clone and a Fastfile importing the clone's CommonFastfile instead of the GitHub one)

# Where helper scripts are fetched from. Override to test a branch/tag: XCODE_SCRIPTS_REF=my-branch
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
XCODE_SCRIPTS_REF="${XCODE_SCRIPTS_REF:-master}"
XCODE_SCRIPTS_RAW="https://raw.githubusercontent.com/InQBarna/xcode-scripts/$XCODE_SCRIPTS_REF"
# Major version of CommonFastfile that generated Fastfiles will follow ("~> 2.0")
XCODE_SCRIPTS_MAJOR="2"

# Prints the path of a file from templates/: the local copy when running from a clone, else downloaded
fetch_template() {
    if [[ -f "$SCRIPT_DIR/templates/$1" ]]; then
        echo "$SCRIPT_DIR/templates/$1"
        return
    fi
    local dest="$(mktemp -d)/$1"
    curl -fsSL "$XCODE_SCRIPTS_RAW/templates/$1" > "$dest" || { echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Could not download templates/$1" >&2; exit 1; }
    echo "$dest"
}

# Prints the path of a helper script from samples/: the local copy when running from a clone, else downloaded
fetch_sample() {
    if [[ -f "$SCRIPT_DIR/samples/$1" ]]; then
        echo "$SCRIPT_DIR/samples/$1"
        return
    fi
    local dest="$(mktemp -d)/$1"
    curl -fsSL "$XCODE_SCRIPTS_RAW/samples/$1" > "$dest" || { echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Could not download samples/$1" >&2; exit 1; }
    echo "$dest"
}


# Writing Gemfile with fastlane
echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Creating Gemfile with fastlane and xcodeproj"
GEMFILE=$(cat <<"EOF"
source "https://rubygems.org"

ruby file: '.ruby-version'

gem 'fastlane'
gem 'xcodeproj'

plugins_path = File.join(File.dirname(__FILE__), 'fastlane', 'Pluginfile')
eval_gemfile(plugins_path) if File.exist?(plugins_path)
EOF
)
echo "$GEMFILE" > Gemfile

# Ruby for a new project: XCODE_SCRIPTS_RUBY if set, else the version in versions.env (the one the smoke test last
# passed with, bumped automatically by a weekly workflow). It is written to the project's committed .ruby-version,
# which the project owns from then on. Bundler is whatever ships with that Ruby (Gemfile.lock records it).
if [[ ! -f .ruby-version ]]; then
    if [[ -n "$XCODE_SCRIPTS_RUBY" ]]; then
        echo "$XCODE_SCRIPTS_RUBY" > .ruby-version
    else
        VERSIONS_ENV="$SCRIPT_DIR/versions.env"
        [[ -f "$VERSIONS_ENV" ]] || { VERSIONS_ENV="$(mktemp -d)/versions.env"; curl -fsSL "$XCODE_SCRIPTS_RAW/versions.env" > "$VERSIONS_ENV" || { echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Could not download versions.env, set XCODE_SCRIPTS_RUBY=x.y.z"; exit 1; }; }
        grep -E '^RUBY_VERSION=[0-9.]+$' "$VERSIONS_ENV" | cut -d= -f2 > .ruby-version
        [[ -s .ruby-version ]] || { echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] No RUBY_VERSION in versions.env, set XCODE_SCRIPTS_RUBY=x.y.z"; rm -f .ruby-version; exit 1; }
    fi
fi
RUBY_VERSION=`tr -d '[:space:]' < .ruby-version`
echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Setting up/configuring setup script with:"
echo " RUBY_VERSION      \"$RUBY_VERSION\" (rbenv, from .ruby-version)"
if [[ ! -d scripts ]]; then
    mkdir scripts
fi
SETUP_SH=$(cat <<"EOF"
#!/bin/bash
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8


echo "[SETUP.SH] Checking brew"
if [[ `which brew` == "" ]]; then
    echo "[SETUP.SH] brew is necessary for installations, specially installing rbenv for ruby"
    echo "[SETUP.SH]  Please install it using: "
    echo "[SETUP.SH]   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)\""
    echo "[SETUP.SH]  Or follow instructions at https://brew.sh"
    exit 1
fi

echo "[SETUP.SH] Checking / installing ruby + bundler (version from .ruby-version)"
export PATH="$(brew --prefix)/bin:$PATH"
if [[ `which rbenv` == "" ]]; then
    echo "[SETUP.SH] Installing rbenv"
    brew install rbenv
fi
RUBY_VERSION=`tr -d '[:space:]' < .ruby-version` || { echo "[SETUP.SH] Missing .ruby-version"; exit 1; }
which gem | grep ".rbenv" || eval "$(rbenv init -)"
if ! rbenv versions --bare | grep -qx "$RUBY_VERSION"; then
    # An old ruby-build does not know recent rubies
    rbenv install -s "$RUBY_VERSION" || { brew upgrade ruby-build; rbenv install -s "$RUBY_VERSION" || exit 1; }
fi
rbenv rehash
ruby --version | grep -F "ruby $RUBY_VERSION" || exit 1
bundle install
#bundle clean

EOF
)
echo "$SETUP_SH" > scripts/setup.sh
chmod +x scripts/setup.sh
echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Running setup script"
scripts/setup.sh || exit 1
# setup.sh ran in its own shell: activate rbenv here too, so the `bundle exec` calls below use the project's Ruby
export PATH="$(brew --prefix)/bin:$PATH"
eval "$(rbenv init - bash)"

# build script
echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Setting up/configuring build script with:"
PROJECT_NAME=`find . -iname *.xcodeproj | head -n 1 | sed -e "s/\.\///g" | sed -e "s/\.xcodeproj//g"`
if [[ $PROJECT_NAME == "" ]]; then
  echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Could not find workspace file, build script won't be generated"
  exit 1
fi
SCHEME_FILE=`find "$PROJECT_NAME.xcodeproj" -iname "*.xcscheme" | grep "xcshareddata/xcschemes" | head -n 1`
if [[ "$SCHEME_FILE" != "" ]]; then
  SCHEME=`echo $SCHEME_FILE | sed -e "s/.*[/]\([^/]*\)\.xcscheme/\1/g"` 
else
  SCHEME=`xcodebuild -project $PROJECT_NAME.xcodeproj -list 2>/dev/null | sed -n '/Schemes/,/^$/p' | grep -v "Tests" | grep -v "^$" | grep -v "Schemes:" | sed -e "s/^[ ]*//g" | head -n 1`
fi
if [[ "$SCHEME_FILE" != "" ]]; then
  echo " SCHEME_FILE       \"$SCHEME_FILE\""
fi
if [[ "$SCHEME" == "" ]]; then
  echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Error: Could not find a valid scheme"
  echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Build script won't be generated"
  exit 1
fi
echo " SCHEME            \"$SCHEME\""
MAIN_TARGET=`xcodebuild -project $PROJECT_NAME.xcodeproj -list 2>/dev/null | sed -n '/Targets/,/^$/p' | grep -v "Tests" | grep -v "^$" | grep -v "Targets:" | sed -e "s/^[ ]*//g" | head -n 1`
if [[ "$MAIN_TARGET" == "" ]]; then
  echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Could not find main app target"
  echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Build script won't be generated"
  exit 1
fi
echo " MAIN_TARGET       \"$MAIN_TARGET\""
TEST_TARGET=`xcodebuild -project $PROJECT_NAME.xcodeproj -list 2>/dev/null | sed -n '/Targets/,/^$/p' | grep "[^U][^I]Tests" | sed -e "s/ *\([a-zA-Z ]*\)/\1/g" | head -n 1`
if [[ "$TEST_TARGET" == "" ]]; then
  TEST_TARGET=`xcodebuild -project $PROJECT_NAME.xcodeproj -list 2>/dev/null | sed -n '/Targets/,/^$/p' | grep "Tests" | sed -e "s/ *\([a-zA-Z ]*\)/\1/g" | head -n 1`
  if [[ "$TEST_TARGET" == "" ]]; then
    TEST_TARGET="${MAIN_TARGET}Tests"
    echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] There's no test target in your project, will use ${TEST_TARGET} for testing purposes... but running tests won't work until you create it"
  fi
fi
echo " TEST_TARGET       \"$TEST_TARGET\""
UI_TEST_TARGET=`xcodebuild -project $PROJECT_NAME.xcodeproj -list 2>/dev/null | sed -n '/Targets/,/^$/p' | grep "UITests" | sed -e "s/^[ ]*//g" | head -n 1`
if [[ "$UI_TEST_TARGET" == "" ]]; then
  echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] There's no UI test target in your project, UI tests will be skipped. Create a target named ${MAIN_TARGET}UITests and set ui_test_target in fastlane/Fastfile to run them"
else
  echo " UI_TEST_TARGET    \"$UI_TEST_TARGET\""
fi
if [[ "$SCHEME_FILE" == "" ]]; then
  echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Warning: There's no shared scheme in your project, for others (and CI) to be able to build it you need a shared scheme (Product > Scheme > Manage Schemes > Shared)"
  echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Make sure the shared scheme is committed (xcshareddata/xcschemes)"
else
  if [[ `git status $SCHEME_FILE | grep Untracked | wc -l` -gt 0 ]]; then
    echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Warning: The file $SCHEME_FILE should be added to the version control system"
  fi
fi

BUILD_SH=$(cat <<"EOF"
#!/bin/bash

# Entry point for local runs and CI (Jenkins / GitHub Actions). The real work lives in the fastlane lanes:
#   (no INTENT)        fastlane build     builds the app, 0 warnings allowed
#   INTENT=test        fastlane test      build + unit tests + coverage + UI tests   (--no-concurrent: sequential UI tests)
#   INTENT=firebase    fastlane firebase  sends a test version to Firebase App Distribution
#   INTENT=testflight  fastlane ship_testflight  sends a version to TestFlight (INTENT=appstore is the old name)
# Optional env: XCODE_EXTRA_PATH (Xcode at /Applications/Xcode$XCODE_EXTRA_PATH.app), RUNTIME, DEVICE, MAX_WARNINGS

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export PATH="$(brew --prefix 2>/dev/null || echo /opt/homebrew)/bin:$PATH"
# Xcode: XCODE_EXTRA_PATH if set, else the version in .xcode-version (installed by xcinstall/install.sh), else /Applications/Xcode.app
if [ "$XCODE_EXTRA_PATH" == "" ] && [ -f .xcode-version ]; then
  WANTED_XCODE=`tr -d '[:space:]' < .xcode-version`
  FOUND_XCODE=`ls -d /Applications/Xcode[-_]${WANTED_XCODE}*.app 2>/dev/null | sort -V | tail -n 1`
  if [ "$FOUND_XCODE" != "" ]; then
    export XCODE_PATH="$FOUND_XCODE/"
  else
    echo "[BUILD.SH] Warning: Xcode $WANTED_XCODE (from .xcode-version) not found in /Applications, using the default one"
  fi
fi
if [ "$XCODE_PATH" == "" ]; then
  export XCODE_PATH="/Applications/Xcode$XCODE_EXTRA_PATH.app/"
fi
export DEVELOPER_DIR="$XCODE_PATH/Contents/Developer/"
echo "[BUILD.SH] Using xcode at $XCODE_PATH. (Use XCODE_EXTRA_PATH to change it)"

echo "[BUILD.SH] Checking input parameters"
if [ "$INTENT" == "testflight" ] || [ "$INTENT" == "appstore" ] || [ "$INTENT" == "firebase" ]; then
  if [[ "$MATCH_PASSPHRASE" == "" ]]; then
    echo "[BUILD.SH] Missing MATCH_PASSPHRASE env variable, configure jenkins bindings / github secrets or please use:"
    echo "[BUILD.SH] export MATCH_PASSPHRASE=XXX"
    exit 1
  fi
fi

echo "[BUILD.SH] Configuring ruby and checking bundler version"
which gem | grep ".rbenv" || eval "$(rbenv init -)"
RUBY_VERSION=`tr -d '[:space:]' < .ruby-version`
ruby --version | grep -F "ruby $RUBY_VERSION" || { echo "[BUILD.SH] Ruby $RUBY_VERSION (from .ruby-version) is not active, run ./scripts/setup.sh"; exit 1; }
bundle --version || exit 1

if [[ "$INTENT" == "testflight" || "$INTENT" == "appstore" ]]; then

  echo "[BUILD.SH] Uploading to TestFlight using fastlane"
  bundle exec fastlane ship_testflight

elif [[ "$INTENT" == "firebase" ]]; then

  if ! which firebase > /dev/null; then
    echo "[BUILD.SH] Installing firebase cli"
    export FIREBASE_PATH="`pwd`/firebase"
    curl -L "https://firebase.tools/bin/macos/latest" --output firebase && chmod +x firebase || exit 1
    export PATH="$PATH:`pwd`"
    which firebase > /dev/null || { echo "[BUILD.SH] Could not find or install firebase cli"; exit 1; }
  fi
  echo "[BUILD.SH] Uploading to firebase using fastlane"
  # If Crashlytics symbols upload fails with SPM, set UPLOAD_SYMBOLS_PATH to the upload-symbols binary in SourcePackages
  bundle exec fastlane firebase

elif [[ "$INTENT" == "test" ]]; then

  if [[ "$*" == "--no-concurrent" ]]; then
    bundle exec fastlane test concurrent_ui_tests:false
  else
    bundle exec fastlane test
  fi

else

  bundle exec fastlane build

fi
EXIT_CODE=$?

unset DEVELOPER_DIR
exit $EXIT_CODE
EOF
)

echo "$BUILD_SH" > scripts/build.sh

chmod +x scripts/build.sh

FASTFILE=$(cat <<"EOF"

__IMPORT_COMMON_FASTFILE__

default_platform(:ios)

before_all do |lane, options|
  # build and test only compile, they don't need App Store Connect access.
  # On CI set ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8 (p8 file content) instead of committing the key.
  unless [:build, :test].include?(lane)
    iq_asc_api_key(key_id: "",
                   issuer_id: "",
                   key_filepath: "./fastlane/AuthKey_XXXXXXX.p8")
  end
end

platform :ios do

  desc "Builds the app for the simulator, fails if there are warnings (used by scripts/build.sh and CI)"
  lane :build do
    iq_build(schemename: "###",
             xcprojname: "###")
  end

  desc "Builds (0 warnings), runs unit tests with coverage and UI tests (used by scripts/build.sh and CI)"
  lane :test do |options|
    iq_test(schemename: "###",
            xcprojname: "###",
            test_target: "###",
            ui_test_target: "###",
            concurrent_ui_tests: options[:concurrent_ui_tests] != false)
  end

  lane :renuke do
    
    match_nuke(type: "development")
    match_nuke(type: "adhoc")
    match_nuke(type: "appstore")
  end

  desc "Submit a new Test Build to Firebase"
  desc "This will also make sure the profile is up to date"
  lane :firebase do
    # This method from include does most of the job
    iq_firebase_v2(schemename: "###",
                  appname: "###",
                  targetname: "###",
                  configuration: "Release",
                  xcprojname: "###",
                  bundleid: "###.###.###",
                  firebaseid: "1:###:ios:###",
                  testers_cs: "")
  end

  desc "Submit a new Build to Apple TestFlight"
  desc "This will also make sure the profile is up to date"
  # Not called "testflight": fastlane already has an action with that name
  lane :ship_testflight do
    iq_testflight(appname: "###",
                  schemename: "###",
                  targetname: "###",
                  configuration: "Release",
                  xcprojname: "###",
                  bundleid: "###.###.###")
  end
end

EOF
)

if [ ! -d fastlane ]; then
  echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Setting up fastlane with"
  if [[ -z "$TEAM_ID" ]]; then
    echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Please provide the team id from developer portal"
    read TEAM_ID
  fi
  echo " TEAM_ID           \"$TEAM_ID\""
  BUNDLE_ID=`xcodebuild -showBuildSettings --scheme="$SCHEME" -target "$MAIN_TARGET" | grep PRODUCT_BUNDLE_IDENTIFIER | sed -e "s/ *PRODUCT_BUNDLE_IDENTIFIER = \(.*\)$/\1/g"`
  echo " BUNDLE_ID         \"$BUNDLE_ID\""
  PRODUCT_NAME=`xcodebuild -showBuildSettings --scheme="$SCHEME" -target "$MAIN_TARGET" | grep FULL_PRODUCT_NAME | sed -e "s/ *FULL_PRODUCT_NAME = \(.*\)\.app$/\1/g"`
  echo " PRODUCT_NAME      \"$PRODUCT_NAME\""
  mkdir fastlane
  if [[ -n "$XCODE_SCRIPTS_USE_LOCAL" ]]; then
    IMPORT_LINE="import '$SCRIPT_DIR/fastlane/CommonFastfile'"
  else
    IMPORT_LINE="import_from_git(url: 'https://github.com/InQBarna/xcode-scripts.git',
               path: 'fastlane/CommonFastfile',
               version: '~> $XCODE_SCRIPTS_MAJOR.0')"
  fi
  echo "${FASTFILE/__IMPORT_COMMON_FASTFILE__/$IMPORT_LINE}" > fastlane/Fastfile
  sed -i "" -e "s/appname: \"###\"/appname: \"$PRODUCT_NAME\"/g" fastlane/Fastfile
  sed -i "" -e "s/schemename: \"###\"/schemename: \"$SCHEME\"/g" fastlane/Fastfile
  sed -i "" -e "s/targetname: \"###\"/targetname: \"$MAIN_TARGET\"/g" fastlane/Fastfile
  sed -i "" -e "s/xcprojname: \"###\"/xcprojname: \"$PROJECT_NAME\"/g" fastlane/Fastfile
  sed -i "" -e "s/ui_test_target: \"###\"/ui_test_target: \"$UI_TEST_TARGET\"/g" fastlane/Fastfile
  sed -i "" -e "s/test_target: \"###\"/test_target: \"$TEST_TARGET\"/g" fastlane/Fastfile
  sed -i "" -e "s/bundleid: \"###.###.###\"/bundleid: \"$BUNDLE_ID\"/g" fastlane/Fastfile

  echo "app_identifier \"$BUNDLE_ID\"" > fastlane/Appfile
  echo "team_id \"$TEAM_ID\"" >> fastlane/Appfile
fi

if [ ! -f fastlane/Matchfile ]; then
  echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Switching to setup_match.sh"
  bash "$(fetch_sample setup_match.sh)"
fi

FOUND_SCRIPT=`grep "BUILD NUMBER FROM FASTLANE TO PLIST" "$PROJECT_NAME.xcodeproj/project.pbxproj"`
if [[ $FOUND_SCRIPT == "" ]]; then
  echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Switching to add_bundleversion_build_phase.rb"
  bundle exec ruby "$(fetch_sample add_bundleversion_build_phase.rb)"
else
  echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Build phase that includes build number to apps plist already found in project"
fi

# CI templates (GitHub Actions and/or Jenkins). Non interactive: CI_PROVIDER=github|jenkins|both|none
install_ci_template() {
    local template="$1" dest="$2"
    if [[ -f "$dest" ]]; then
        echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] $dest already exists, not overwriting it"
        return
    fi
    mkdir -p "$(dirname "$dest")"
    if [[ -f "$SCRIPT_DIR/templates/$template" ]]; then
        cp "$SCRIPT_DIR/templates/$template" "$dest"
    else
        curl -fsSL "$XCODE_SCRIPTS_RAW/templates/$template" > "$dest" || { rm -f "$dest"; echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Could not download template $template"; return; }
    fi
    echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Created $dest"
}
CI_PROVIDER="${CI_PROVIDER:-}"
if [[ -z "$CI_PROVIDER" ]]; then
    echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Which CI templates do you want? [g]ithub actions (default), [j]enkins, [b]oth, [n]one"
    read CI_ANSWER
    case "$CI_ANSWER" in
        j*|J*) CI_PROVIDER="jenkins" ;;
        b*|B*) CI_PROVIDER="both" ;;
        n*|N*) CI_PROVIDER="none" ;;
        *) CI_PROVIDER="github" ;;
    esac
fi
if [[ "$CI_PROVIDER" == "github" || "$CI_PROVIDER" == "both" ]]; then
    install_ci_template github-actions/ci.yml .github/workflows/ci.yml
    install_ci_template github-actions/distribute.yml .github/workflows/distribute.yml
    install_ci_template github-actions/dependabot.yml .github/dependabot.yml
fi
if [[ "$CI_PROVIDER" == "jenkins" || "$CI_PROVIDER" == "both" ]]; then
    install_ci_template jenkins/Jenkinsfile Jenkinsfile
fi

if [[ ! -f .xcode-version ]]; then
    xcodebuild -version | head -n 1 | sed -e "s/Xcode //" > .xcode-version
    echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Created .xcode-version with `cat .xcode-version` (Xcode used by build.sh and CI, edit if needed)"
fi

# Doctor: checks the project setup and says how to fix what is missing
if [[ ! -f scripts/doctor.sh ]]; then
    cp "$(fetch_template doctor.sh)" scripts/doctor.sh && chmod +x scripts/doctor.sh && echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Created scripts/doctor.sh (run it any time to check the setup)"
fi

echo "[CREATE_SETUP_BUILD_SCRIPTS.SH] Settting up gitignore"
curl "https://www.toptal.com/developers/gitignore/api/xcode,swift,macos,swiftpackagemanager,swiftpm" > .gitignore
sed -i "" -e "/^\*\.xcodeproj$/d" .gitignore
cat >> .gitignore <<GITIGNORE_EOF
fastlane/README.md

# Build / test artifacts (scripts/build.sh and the fastlane build/test lanes)
deriveddata/
gymbuildlog/
coverage/
fastlane/test_output/
fastlane/test_output_ui/
fastlane/report.xml

# Secrets: App Store Connect API keys and local env files (use CI secrets instead)
fastlane/AuthKey_*.p8
fastlane/.env*
!fastlane/.env.example
GITIGNORE_EOF
