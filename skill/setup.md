# Setup — Helius + Rust

## Cargo.toml

```toml
[package]
name = "my-solana-bot"
version = "0.1.0"
edition = "2021"

[dependencies]
# Async runtime
tokio = { version = "1", features = ["full"] }

# WebSocket (accountSubscribe)
tokio-tungstenite = { version = "0.21", features = ["native-tls"] }
futures-util = "0.3"

# Solana RPC (blocking client wrapped in spawn_blocking)
solana-client = "1.18.26"
solana-sdk = "1.18.26"

# HTTP (JSON-RPC calls, REST fallbacks)
reqwest = { version = "0.11", features = ["json", "rustls-tls"], default-features = false }

# JSON
serde = { version = "1", features = ["derive"] }
serde_json = "1"

# Encoding
bs58 = "0.5"
base64 = "0.22"

# Utilities
anyhow = "1.0"
dotenv = "0.15"
once_cell = "1"
dashmap = "6"

[profile.release]
opt-level = 3
lto = true
codegen-units = 1
```

## Environment variables

```env
HELIUS_API_KEY=your_key_here
```

Load at startup:

```rust
dotenv::dotenv().ok();
let helius_key = std::env::var("HELIUS_API_KEY").expect("HELIUS_API_KEY required");
```

## Endpoint helpers

```rust
fn helius_rpc(key: &str) -> String {
    format!("https://mainnet.helius-rpc.com/?api-key={}", key)
}

fn helius_ws(key: &str) -> String {
    format!("wss://mainnet.helius-rpc.com/?api-key={}", key)
}
```

## RPC client setup

Helius works fine with the standard `solana-client` `RpcClient`. Use `spawn_blocking` because
`RpcClient` is synchronous:

```rust
use solana_client::rpc_client::RpcClient;
use solana_sdk::commitment_config::CommitmentConfig;

let rpc = RpcClient::new_with_timeout_and_commitment(
    helius_rpc(&key),
    std::time::Duration::from_secs(5),
    CommitmentConfig::processed(),
);
```

For HTTP JSON-RPC calls directly (faster, no `spawn_blocking`):

```rust
let client = reqwest::Client::builder()
    .timeout(std::time::Duration::from_secs(4))
    .build()?;
```
