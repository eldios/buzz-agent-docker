# buzz-agent-docker

Container image for running a [Buzz](https://github.com/block/buzz) agent
headless, without Buzz Desktop. It packages the upstream `buzz-acp` harness
(from `ghcr.io/block/buzz-sprig`) together with the main ACP agent runtimes:

- `claude-agent-acp` - Claude Code, billed to a Claude subscription
- `codex-acp` - Codex, billed to a ChatGPT plan
- `goose` - Block's Goose, provider-configurable
- `buzz-agent` - upstream minimal runtime for API keys: OpenRouter,
  Anthropic, OpenAI-compatible, Databricks

A Buzz agent is defined by a keypair, an auth tag, and a relay URL handed to
the `buzz-acp` harness; the desktop is one launcher among many (see the
upstream `docs/remote-agents.md`). This image is a Compose-friendly launcher:
one always-on container per agent, next to the relay or anywhere else.

## Image contents

| Piece | Source |
|-------|--------|
| `buzz-acp`, `buzz-agent`, `buzz` CLI, git helpers | static `sprig` multicall binary from `ghcr.io/block/buzz-sprig`, digest-pinned |
| `claude-agent-acp` | npm `@agentclientprotocol/claude-agent-acp`, version-pinned |
| `codex-acp` | npm `@agentclientprotocol/codex-acp`, version-pinned |
| `goose` | official release tarball from `block/goose`, version-pinned (upstream publishes no checksums) |
| Node.js runtime | `node:24-bookworm-slim` (current LTS) |

The Claude Code CLI itself ships as a native optional dependency of the
adapter's SDK and is installed with it.

## Usage

See `compose.example.yaml` for a full stack definition. Minimal run:

```bash
docker run -d --name my-agent \
  -e BUZZ_RELAY_URL=wss://relay.example.com \
  -e BUZZ_PRIVATE_KEY=<64-char-hex> \
  -e BUZZ_AUTH_TAG=<auth-tag> \
  -e CLAUDE_CODE_OAUTH_TOKEN=<token> \
  -v my-agent-home:/home/agent \
  -v my-agent-workspace:/workspace \
  ghcr.io/eldios/buzz-agent:latest
```

### Environment

| Variable | Meaning |
|----------|---------|
| `BUZZ_RELAY_URL` | Relay websocket URL (`ws://` or `wss://`) |
| `BUZZ_PRIVATE_KEY` | Agent identity, 64-char hex private key (required) |
| `BUZZ_AUTH_TAG` | NIP-OA auth tag for the relay |
| `BUZZ_ACP_AGENT_OWNER` | Owner pubkey for the `respond-to=owner-only` gate |
| `BUZZ_ACP_AGENT_COMMAND` | which runtime to spawn, see below |
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude subscription token from `claude setup-token` |

`buzz-acp --help` documents the full harness option set (idle timeout, turn
duration cap, MCP command).

### Choosing the runtime

| Runtime | Settings |
|---------|----------|
| Claude Code (default) | `BUZZ_ACP_AGENT_COMMAND=claude-agent-acp` |
| Codex | `BUZZ_ACP_AGENT_COMMAND=codex-acp` |
| Goose | `BUZZ_ACP_AGENT_COMMAND=goose`, `BUZZ_ACP_AGENT_ARGS=acp`, plus Goose's own provider env (`GOOSE_PROVIDER`, ...) |
| OpenRouter / API keys | `BUZZ_ACP_AGENT_COMMAND=buzz-agent`, `BUZZ_AGENT_PROVIDER=openrouter` (or `anthropic`, `openai`, `databricks`) and the matching key, e.g. `OPENROUTER_API_KEY` |

### Authentication

**Claude, token (recommended):** on any machine with the Claude CLI run
`claude setup-token` (requires a Claude subscription), then set the result as
`CLAUDE_CODE_OAUTH_TOKEN`.

**Claude, interactive:** leave the token unset, then once per volume:

```bash
docker exec -it my-agent claude-agent-acp --cli
```

and complete the login prompt. Credentials persist in the `/home/agent`
volume.

**Codex:** log in on any machine, copy `~/.codex/auth.json` into the
`/home/agent` volume, and set `BUZZ_ACP_AGENT_COMMAND=codex-acp`.

### Provisioning an identity

A relay running with `BUZZ_REQUIRE_RELAY_MEMBERSHIP=true` and
`BUZZ_ALLOW_NIP_OA_AUTH=true` admits an agent key when the agent presents a
NIP-OA owner attestation and the owner is a relay member.
The `mint-auth-tag` tool baked into the image generates both pieces
(validated against the NIP-OA specification's test vector). No host
tooling needed beyond Docker:

```bash
docker run --rm --entrypoint mint-auth-tag ghcr.io/eldios/buzz-agent:latest --generate
# -> agent_secret_hex (BUZZ_PRIVATE_KEY) + agent_pubkey_hex

docker run --rm -e OWNER_SECRET_HEX=<owner-hex-secret> \
  --entrypoint mint-auth-tag ghcr.io/eldios/buzz-agent:latest <agent-pubkey-hex>
# -> BUZZ_AUTH_TAG
```

Run it on the owner's machine: the owner secret goes only into the
ephemeral container's environment and only the public attestation goes
into the stack. Channel membership is separate from relay access; add the
agent's pubkey to the channels it should read.

### One agent, one instance

Nothing in the protocol prevents two launchers from running the same agent
identity; they will both answer every event. When an agent moves into a
container, disable it in every Buzz Desktop that also has it configured.

## Development

`nix develop` provides every tool the CI runs; `just ci` runs the same gates
(hadolint, actionlint, shellcheck, build, smoke test). `just check-versions`
compares the pinned adapter versions and sprig digest against upstream.

## License

MIT
