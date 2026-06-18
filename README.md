# helius-rust-skill

A Claude Code skill for building Solana bots and indexers in Rust using the Helius RPC.

Derived from production trading bots running on Solana mainnet — not toy demos.

## What this covers

- Setting up a Rust project with the right Helius-compatible dependencies
- Making JSON-RPC calls (`getAccountInfo`, `getSignaturesForAddress`) with proper 429 handling
- Real-time account monitoring via `accountSubscribe` WebSocket
- A lock-free circuit breaker pattern for rate limit resilience
- Reading on-chain prices directly from account bytes (bonding curves, AMM vaults)
- WebSocket → REST polling fallback for production resilience

## Who this is for

Rust developers building on Solana who need:
- Sniper bots that react to on-chain events in milliseconds
- Copy trading systems that monitor wallets in real time
- Indexers that track account state changes
- Any bot that needs Helius to stay reliable under load

## Install

```bash
# clone into your project's .claude/ directory
git clone https://github.com/YOUR_USER/helius-rust-skill .claude/skills/helius-rust-skill

# or run the installer
bash .claude/skills/helius-rust-skill/install.sh
```

## Structure

```
skill/
  SKILL.md              # Entry point — routes to topic files
  setup.md              # Cargo.toml, env vars, RPC client setup
  rpc.md                # getAccountInfo, getSignaturesForAddress, parallel calls
  websocket.md          # accountSubscribe, reconnect loop, channels
  circuit-breaker.md    # Lock-free 429 circuit breaker (atomic, static-safe)
  price-feed.md         # On-chain bonding curve prices, WS + REST fallback
rules/
  helius-rust.md        # Coding conventions enforced by Claude
```

## Usage

Reference the entry point in your Claude Code session:

```
Read .claude/skills/helius-rust-skill/skill/SKILL.md
```

Claude will load only the topic files relevant to your current task.

## License

MIT
