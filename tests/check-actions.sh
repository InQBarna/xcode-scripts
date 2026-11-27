#!/bin/bash
# Reports GitHub Actions used by templates/ and .github/ whose major version is behind the latest release.
# Needs the gh CLI (authenticated). Exit code 1 when something is outdated.
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
OUTDATED=0
for use in $(grep -rhoE "uses: [A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@v[0-9]+" templates .github | sed -e "s/uses: //" | sort -u); do
    action="${use%@*}"
    used="${use#*@v}"
    latest=$(gh api "repos/$action/releases/latest" --jq .tag_name 2>/dev/null | sed -e "s/^v//" | cut -d. -f1)
    if [[ -z "$latest" ]]; then
        echo "?  $use: could not read the latest release"
    elif [[ "$latest" -gt "$used" ]]; then
        echo "OUTDATED $use -> v$latest"
        OUTDATED=1
    else
        echo "ok $use"
    fi
done
exit $OUTDATED
