# buzz-agent-docker task runner. Run `just` for the list; the dev shell
# (flake.nix) provides just, hadolint, actionlint, shellcheck, act, curl, jq.

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

# Compare the pinned adapter versions and sprig digest against upstream
check-versions:
    #!/usr/bin/env bash
    set -euo pipefail
    for pkg in CLAUDE_ACP:claude-agent-acp CODEX_ACP:codex-acp; do
        arg="${pkg%%:*}_VERSION"; name="${pkg##*:}"
        pinned="$(grep -oE "^ARG ${arg}=.*" {{dockerfile}} | cut -d= -f2)"
        latest="$(curl -fsSL "https://registry.npmjs.org/@agentclientprotocol%2F${name}" | jq -r '.["dist-tags"].latest')"
        printf '%-18s pinned %-8s latest %s\n' "$name" "$pinned" "$latest"
    done
    goose_pinned="$(grep -oE '^ARG GOOSE_VERSION=.*' {{dockerfile}} | cut -d= -f2)"
    goose_latest="$(curl -fsSL https://api.github.com/repos/block/goose/releases/latest | jq -r .tag_name)"
    printf '%-18s pinned %-8s latest %s\n' "goose" "$goose_pinned" "${goose_latest#v}"
    pinned_digest="$(grep -oE 'buzz-sprig:main@[a-z0-9:]+' {{dockerfile}} | cut -d@ -f2)"
    token="$(curl -fsSL "https://ghcr.io/token?scope=repository:block/buzz-sprig:pull" | jq -r .token)"
    latest_digest="$(curl -fsSI -H "Authorization: Bearer $token" \
        -H "Accept: application/vnd.oci.image.index.v1+json" \
        "https://ghcr.io/v2/block/buzz-sprig/manifests/main" \
        | grep -i docker-content-digest | tr -d '\r' | awk '{print $2}')"
    printf '%-18s pinned %s\n%-18s latest %s\n' "sprig" "$pinned_digest" "" "$latest_digest"
