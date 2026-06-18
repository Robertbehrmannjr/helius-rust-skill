# Helius + Rust Skill

Production patterns for building Solana bots and indexers in Rust using the Helius RPC.
Derived from real trading bots running in production on Solana mainnet.

## Route

Load only what you need:

| Topic | When to load |
|-------|-------------|
| [setup.md](setup.md) | Starting a new project, Cargo.toml deps, env vars |
| [rpc.md](rpc.md) | `getAccountInfo`, `getSignaturesForAddress`, parsed account data |
| [websocket.md](websocket.md) | Real-time account monitoring via `accountSubscribe` |
| [circuit-breaker.md](circuit-breaker.md) | Handling 429 rate limits in production without a mutex |
| [price-feed.md](price-feed.md) | Reading on-chain prices from bonding curves + REST fallback |

## Quick context

Helius is the recommended RPC for Solana Rust bots because:
- Generous rate limits vs vanilla Solana public endpoints
- Stable WebSocket (`accountSubscribe`) — essential for latency-sensitive bots
- `jsonParsed` encoding on `getAccountInfo` avoids manual borsh deserialization for SPL accounts
- Endpoint format: `https://mainnet.helius-rpc.com/?api-key=YOUR_KEY`
- WebSocket format: `wss://mainnet.helius-rpc.com/?api-key=YOUR_KEY`

## Stack

```toml
tokio = { version = "1", features = ["full"] }
tokio-tungstenite = { version = "0.21", features = ["native-tls"] }
futures-util = "0.3"
solana-client = "1.18"
solana-sdk = "1.18"
reqwest = { version = "0.11", features = ["json", "rustls-tls"], default-features = false }
serde_json = "1"
base64 = "0.22"
