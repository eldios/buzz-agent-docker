# syntax=docker/dockerfile:1

# Headless Buzz agent runtime: the buzz-acp harness from the upstream sprig
# image plus the main ACP agent runtimes - Claude Code and Codex
# (subscription-billed), Goose, and the bundled buzz-agent for
# OpenRouter/Anthropic/OpenAI API keys. Runs anywhere Docker runs; no Buzz
# Desktop needed.
#
# The harness and its sidecar tools come from ghcr.io/block/buzz-sprig, a
# static musl multicall binary (buzz-acp, buzz-agent, buzz CLI, git helpers).
# The Claude and Codex adapters are the same npm packages Buzz Desktop
# installs locally; Goose comes from its official release tarball.

ARG NODE_VERSION=24
ARG CLAUDE_ACP_VERSION=0.66.0
ARG CODEX_ACP_VERSION=1.2.0
ARG GOOSE_VERSION=1.46.0

# Upstream publishes only moving tags (main, sha-*); the digest is the pin.
FROM ghcr.io/block/buzz-sprig:main@sha256:77757a96883d2560f9dfce9eb4ce2ea50e890ab948e8473956dafe39087c91f1 AS sprig

FROM node:${NODE_VERSION}-bookworm-slim AS goose-fetch

ARG GOOSE_VERSION
ARG TARGETARCH

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends bzip2 ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /out

# Upstream publishes no checksums or signatures for release assets; the
# version pin and the TLS channel are the only integrity guarantees.
RUN set -eu; \
    case "${TARGETARCH}" in \
        amd64) arch=x86_64 ;; \
        arm64) arch=aarch64 ;; \
        *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/block/goose/releases/download/v${GOOSE_VERSION}/goose-${arch}-unknown-linux-gnu.tar.gz" \
        | tar -xz; \
    test -x goose

FROM node:${NODE_VERSION}-bookworm-slim

ARG CLAUDE_ACP_VERSION
ARG CODEX_ACP_VERSION

# The base image's node user holds uid 1000, so the agent user takes 1001.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends bash ca-certificates curl git \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -d /home/agent -s /bin/bash -u 1001 agent \
    && install -d -o agent -g agent /workspace

# The sprig multicall binary dispatches on argv[0]; the symlink set mirrors
# the upstream image.
COPY --from=sprig /usr/local/bin/sprig /usr/local/bin/sprig
COPY --from=goose-fetch /out/goose /usr/local/bin/goose
RUN for name in \
      buzz-acp buzz-agent buzz-dev-mcp rg tree buzz \
      git-credential-nostr git-sign-nostr; do \
        ln -s sprig "/usr/local/bin/$name"; \
    done \
    && git config --system gpg.format x509 \
    && git config --system gpg.x509.program /usr/local/bin/git-sign-nostr \
    && git config --system commit.gpgSign true \
    && git config --system tag.gpgSign true

# The Claude adapter pulls @anthropic-ai/claude-agent-sdk, whose native CLI
# ships as a platform-specific optional dependency (glibc variant on this
# base). The Codex adapter bundles its own runtime.
RUN npm install -g --omit=dev \
      "@agentclientprotocol/claude-agent-acp@${CLAUDE_ACP_VERSION}" \
      "@agentclientprotocol/codex-acp@${CODEX_ACP_VERSION}" \
    && npm cache clean --force

COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint

# Which agent the harness spawns. Alternatives: codex-acp, goose (with
# BUZZ_ACP_AGENT_ARGS=acp), or buzz-agent for API-key providers including
# OpenRouter.
ENV BUZZ_ACP_AGENT_COMMAND=claude-agent-acp \
    BUZZ_ACP_AGENT_ARGS="" \
    HOME=/home/agent

WORKDIR /home/agent
USER 1001:1001

# /home/agent holds the agent's LLM credentials (~/.claude, ~/.codex) and
# must persist across container recreation; /workspace holds its files.
VOLUME ["/home/agent", "/workspace"]

ENTRYPOINT ["/usr/local/bin/entrypoint"]
