#!/usr/bin/env bash
# Smoke tests for the image. Checks the things most likely to break: the
# static sprig binary failing on a glibc base, the npm adapters missing their
# runtime, and the entrypoint not failing fast without an identity.
set -euo pipefail

IMAGE="${IMAGE:-buzz-agent-local}"
DOCKERFILE="${DOCKERFILE:-Dockerfile}"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=1; }

tag="${IMAGE}:test"

if docker image inspect "$tag" >/dev/null 2>&1; then
    echo "using existing image ${tag}"
else
    echo "building ${tag}"
    docker build -t "$tag" -f "$DOCKERFILE" .
fi

# The harness binary must run on this base: a musl/glibc mismatch fails here.
if docker run --rm --entrypoint buzz-acp "$tag" --help 2>&1 | grep -q "ACP harness"; then
    pass "buzz-acp runs and prints its help"
else
    fail "buzz-acp does not run"
fi

# The buzz CLI personality of the multicall binary.
if docker run --rm --entrypoint buzz "$tag" --help >/dev/null 2>&1; then
    pass "buzz CLI runs"
else
    fail "buzz CLI does not run"
fi

# Both adapters must resolve their node runtime and print a version.
claude_acp_pin="$(grep -oE '^ARG CLAUDE_ACP_VERSION=.*' "$DOCKERFILE" | cut -d= -f2)"
if docker run --rm --entrypoint claude-agent-acp "$tag" --version 2>&1 | grep -q "$claude_acp_pin"; then
    pass "claude-agent-acp ${claude_acp_pin} responds"
else
    fail "claude-agent-acp does not respond with the pinned version"
fi

if docker run --rm --entrypoint codex-acp "$tag" --version >/dev/null 2>&1; then
    pass "codex-acp responds"
else
    fail "codex-acp does not respond"
fi

# The bundled Claude Code CLI is a native optional dependency; it must have
# installed the variant matching the image's libc.
if docker run --rm --entrypoint claude-agent-acp "$tag" --cli --version >/dev/null 2>&1; then
    pass "bundled Claude Code CLI runs"
else
    fail "bundled Claude Code CLI does not run"
fi

# Goose comes from the release tarball and must match the pin.
goose_pin="$(grep -oE '^ARG GOOSE_VERSION=.*' "$DOCKERFILE" | cut -d= -f2)"
if docker run --rm --entrypoint goose "$tag" --version 2>&1 | grep -q "$goose_pin"; then
    pass "goose ${goose_pin} responds"
else
    fail "goose does not respond with the pinned version"
fi

# The API-key runtime (OpenRouter and friends) must fail fast asking for a
# provider, not crash or hang. It exits nonzero by design, so capture the
# output instead of gating on the pipeline status.
buzz_agent_out="$(docker run --rm --entrypoint buzz-agent "$tag" 2>&1 || true)"
if grep -q "BUZZ_AGENT_PROVIDER" <<<"$buzz_agent_out"; then
    pass "buzz-agent asks for a provider"
else
    fail "buzz-agent does not report its provider requirement"
fi

# Without an identity the entrypoint must fail fast, not hang.
if docker run --rm "$tag" >/dev/null 2>&1; then
    fail "entrypoint succeeded without BUZZ_PRIVATE_KEY"
else
    pass "entrypoint fails fast without an identity"
fi

exit "$FAILED"
