# Price Feed — On-Chain Prices via Helius

Reading prices directly from on-chain account data avoids oracle dependencies and latency.
This covers bonding curves (Pump.fun) as a concrete example, but the pattern applies to
any on-chain AMM or vault account.

## Reading price from a Pump.fun bonding curve

Bonding curve accounts store virtual reserves at fixed byte offsets.
Parse them directly from raw account bytes — no borsh crate needed:

```rust
fn parse_bonding_curve_price(data: &[u8]) -> Option<f64> {
    if data.len() < 24 {
        return None;
    }

    // Pump.fun bonding curve layout:
    // bytes  0..8  — discriminator (skip)
    // bytes  8..16 — virtualTokenReserves (u64 LE, in token units * 1e6)
    // bytes 16..24 — virtualSolReserves (u64 LE, in lamports)
    let virtual_tokens = u64::from_le_bytes(data[8..16].try_into().ok()?) as f64;
    let virtual_sol    = u64::from_le_bytes(data[16..24].try_into().ok()?) as f64;

    if virtual_tokens <= 0.0 || virtual_sol <= 0.0 {
        return None;
    }

    // price = SOL per token
    let price = (virtual_sol / 1_000_000_000.0) / (virtual_tokens / 1_000_000.0);

    if price.is_finite() && price > 0.0 { Some(price) } else { None }
}
```

## Fetching account bytes via RPC (one-shot)

```rust
use solana_client::rpc_client::RpcClient;
use solana_sdk::{commitment_config::CommitmentConfig, pubkey::Pubkey};
use std::str::FromStr;

async fn price_from_account(pubkey: &str, helius_key: &str) -> Option<f64> {
    let rpc_url = format!("https://mainnet.helius-rpc.com/?api-key={}", helius_key);
    let pubkey_str = pubkey.to_string();

    // RpcClient is blocking — wrap in spawn_blocking
    tokio::task::spawn_blocking(move || {
        let rpc = RpcClient::new_with_timeout_and_commitment(
            rpc_url,
            std::time::Duration::from_secs(5),
            CommitmentConfig::processed(),
        );
        let pk = Pubkey::from_str(&pubkey_str).ok()?;
        let account = rpc.get_account(&pk).ok()?;
        parse_bonding_curve_price(&account.data)
    })
    .await
    .ok()
    .flatten()
}
```

## Real-time feed via accountSubscribe + REST fallback

Production pattern: prefer WebSocket, fall back to polling if WS fails.

```rust
use tokio::sync::mpsc;

pub async fn start_price_feed(pubkey: String, helius_key: String, tx: mpsc::Sender<f64>) {
    match feed_via_ws(&pubkey, &helius_key, tx).await {
        FeedResult::Exited => {},
        FeedResult::Failed(tx) => {
            println!("WS failed — falling back to REST polling");
            feed_via_polling(pubkey, tx).await;
        }
    }
}

enum FeedResult {
    Exited,                      // consumer dropped — clean shutdown
    Failed(mpsc::Sender<f64>),   // WS broke — return sender for fallback
}

async fn feed_via_ws(pubkey: &str, helius_key: &str, tx: mpsc::Sender<f64>) -> FeedResult {
    use futures_util::{SinkExt, StreamExt};
    use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
    use tokio_tungstenite::tungstenite::protocol::Message;

    let ws_url = format!("wss://mainnet.helius-rpc.com/?api-key={}", helius_key);

    let (ws_stream, _) = match tokio_tungstenite::connect_async(&ws_url).await {
        Ok(c) => c,
        Err(_) => return FeedResult::Failed(tx),
    };

    let (mut write, mut read) = ws_stream.split();

    let sub = serde_json::json!({
        "jsonrpc": "2.0", "id": 1,
        "method": "accountSubscribe",
        "params": [pubkey, { "encoding": "base64", "commitment": "processed" }]
    });

    if write.send(Message::Text(sub.to_string())).await.is_err() {
        return FeedResult::Failed(tx);
    }

    while let Some(msg) = read.next().await {
        if tx.is_closed() {
            return FeedResult::Exited;
        }

        let text = match msg {
            Ok(Message::Text(t))  => t,
            Ok(Message::Close(_)) => return FeedResult::Failed(tx),
            Err(_)                => return FeedResult::Failed(tx),
            _                     => continue,
        };

        let parsed: serde_json::Value = match serde_json::from_str(&text) {
            Ok(v) => v,
            Err(_) => continue,
        };

        if parsed["method"].as_str() != Some("accountNotification") {
            continue;
        }

        // Account closed (rug, graduation) — drop sender to signal consumer
        if parsed["params"]["result"]["value"]["lamports"].as_u64().unwrap_or(1) == 0 {
            drop(tx);
            return FeedResult::Exited;
        }

        if let Some(b64) = parsed["params"]["result"]["value"]["data"][0].as_str() {
            if let Ok(bytes) = BASE64.decode(b64) {
                if let Some(price) = parse_bonding_curve_price(&bytes) {
                    if tx.send(price).await.is_err() {
                        return FeedResult::Exited;
                    }
                }
            }
        }
    }

    FeedResult::Exited
}

async fn feed_via_polling(mint: String, tx: mpsc::Sender<f64>) {
    let client = reqwest::Client::new();
    loop {
        if tx.is_closed() { break; }
        // fetch price from DexScreener, PumpPortal, etc.
        tokio::time::sleep(std::time::Duration::from_secs(2)).await;
    }
}
```

## Key invariant

Dropping the `mpsc::Sender` is the shutdown signal to the consumer.
When the bonding curve account hits zero lamports (rug or Raydium graduation),
drop the sender immediately — the consumer's `recv()` returns `None` and exits
without waiting for a timeout.
