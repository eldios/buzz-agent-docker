# buzz-agent-docker task runner. Run `just` for the list; the dev shell
# (flake.nix) provides just, hadolint, actionlint, shellcheck, act, curl, jq,
# python3.

set shell := ["bash", "-euo", "pipefail", "-c"]

image := "buzz-agent-local"
dockerfile := "Dockerfile"

default:
    @just --list

# Every gate the CI workflow runs, in the same order
ci: lint build test

# Lint the container definition, the workflows, and the shell scripts
lint:
    hadolint {{dockerfile}}
    actionlint
    shellcheck test/smoke.sh entrypoint.sh scripts/extract-desktop-agents.sh profile.d/agent-tools.sh
    python3 -m py_compile scripts/bump-pins.py

# Build the image
build:
    docker build -t {{image}}:test -f {{dockerfile}} .

# Smoke test: the harness, both adapters, and the bundled CLI must run
test:
    IMAGE={{image}} ./test/smoke.sh

# Run the CI jobs for real in the runner image
workflow-check:
    act -j lint --pull=false
    act -j smoke --pull=false

# Parse-only check of the workflow
workflow-parse:
    act -n

# Shell inside the image
shell:
    docker run --rm -it --entrypoint bash {{image}}:test

# Compare the pinned runtimes and the sprig digest against upstream
check-versions:
    #!/usr/bin/env bash
    set -euo pipefail
    scripts/bump-pins.py check
    pinned_digest="$(grep -oE 'buzz-sprig:main@[a-z0-9:]+' {{dockerfile}} | cut -d@ -f2)"
    token="$(curl -fsSL "https://ghcr.io/token?scope=repository:block/buzz-sprig:pull" | jq -r .token)"
    latest_digest="$(curl -fsSI -H "Authorization: Bearer $token" \
        -H "Accept: application/vnd.oci.image.index.v1+json" \
        "https://ghcr.io/v2/block/buzz-sprig/manifests/main" \
        | grep -i docker-content-digest | tr -d '\r' | awk '{print $2}')"
    printf '%-18s pinned %s\n%-18s latest %s\n' "sprig" "$pinned_digest" "" "$latest_digest"

# Move the runtime pins to the newest release of their major (what the nightly
# auto-update workflow runs); sprig moves by hand, together with the relay
bump:
    scripts/bump-pins.py update
