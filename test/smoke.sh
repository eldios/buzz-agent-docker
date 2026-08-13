#!/usr/bin/env bash
# Smoke tests for the image. Checks the things most likely to break: the
# static sprig binary failing on a glibc base, the npm adapters missing their
# runtime, and the entrypoint not failing fast without an identity.
#
# Every check captures the container output and greps the capture. Piping
# docker straight into grep -q is a race under pipefail: grep exits on the
# first match, docker dies of SIGPIPE, and the pipeline fails despite the
# match.
set -euo pipefail

IMAGE="${IMAGE:-buzz-agent-local}"
DOCKERFILE="${DOCKERFILE:-Dockerfile}"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=1; }

# run_in <entrypoint> [args...] -> captured stdout+stderr, exit tolerated
run_in() {
    local entrypoint="$1"
    shift
    docker run --rm --entrypoint "$entrypoint" "$tag" "$@" 2>&1 || true
}

tag="${IMAGE}:test"

if docker image inspect "$tag" >/dev/null 2>&1; then
    echo "using existing image ${tag}"
else
    echo "building ${tag}"
    docker build -t "$tag" -f "$DOCKERFILE" .
fi

# The harness binary must run on this base: a musl/glibc mismatch fails here.
if grep -q "ACP harness" <<<"$(run_in buzz-acp --help)"; then
    pass "buzz-acp runs and prints its help"
else
    fail "buzz-acp does not run"
fi

# The buzz CLI personality of the multicall binary.
if grep -q "Buzz CLI" <<<"$(run_in buzz --help)"; then
    pass "buzz CLI runs"
else
    fail "buzz CLI does not run"
fi

# Both adapters must resolve their node runtime and print the pinned version.
claude_acp_pin="$(grep -oE '^ARG CLAUDE_ACP_VERSION=.*' "$DOCKERFILE" | cut -d= -f2)"
if grep -q "$claude_acp_pin" <<<"$(run_in claude-agent-acp --version)"; then
    pass "claude-agent-acp ${claude_acp_pin} responds"
else
    fail "claude-agent-acp does not respond with the pinned version"
fi

codex_acp_pin="$(grep -oE '^ARG CODEX_ACP_VERSION=.*' "$DOCKERFILE" | cut -d= -f2)"
if grep -q "$codex_acp_pin" <<<"$(run_in codex-acp --version)"; then
    pass "codex-acp ${codex_acp_pin} responds"
else
    fail "codex-acp does not respond with the pinned version"
fi

# The bundled Claude Code CLI is a native optional dependency; it must have
# installed the variant matching the image's libc.
if grep -q "Claude Code" <<<"$(run_in claude-agent-acp --cli --version)"; then
    pass "bundled Claude Code CLI runs"
else
    fail "bundled Claude Code CLI does not run"
fi

# Goose comes from the release tarball and must match the pin.
goose_pin="$(grep -oE '^ARG GOOSE_VERSION=.*' "$DOCKERFILE" | cut -d= -f2)"
if grep -q "$goose_pin" <<<"$(run_in goose --version)"; then
    pass "goose ${goose_pin} responds"
else
    fail "goose does not respond with the pinned version"
fi

# The API-key runtime (OpenRouter and friends) must fail fast asking for a
# provider, not crash or hang. It exits nonzero by design.
if grep -q "BUZZ_AGENT_PROVIDER" <<<"$(run_in buzz-agent)"; then
    pass "buzz-agent asks for a provider"
else
    fail "buzz-agent does not report its provider requirement"
fi

# The identity tool must generate a keypair and mint a tag that passes its
# own verification (the script self-verifies before printing).
keypair="$(run_in mint-auth-tag --generate)"
agent_pub="$(grep -oE '"agent_pubkey_hex": "[0-9a-f]{64}"' <<<"$keypair" | grep -oE '[0-9a-f]{64}')"
agent_sec="$(grep -oE '"agent_secret_hex": "[0-9a-f]{64}"' <<<"$keypair" | grep -oE '[0-9a-f]{64}')"
if [[ -n "$agent_pub" && -n "$agent_sec" ]]; then
    pass "mint-auth-tag generates a keypair"
else
    fail "mint-auth-tag does not generate a keypair"
fi

tag_out="$(docker run --rm -e OWNER_SECRET_HEX="$agent_sec" --entrypoint mint-auth-tag "$tag" "$agent_pub" 2>&1 || true)"
if grep -q '^\["auth",' <<<"$tag_out"; then
    pass "mint-auth-tag mints a self-verified tag"
else
    fail "mint-auth-tag does not mint a tag"
fi

# Without an identity the entrypoint must fail fast, not hang.
if docker run --rm "$tag" >/dev/null 2>&1; then
    fail "entrypoint succeeded without BUZZ_PRIVATE_KEY"
else
    pass "entrypoint fails fast without an identity"
fi

exit "$FAILED"
