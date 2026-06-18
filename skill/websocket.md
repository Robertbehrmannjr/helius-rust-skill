# WebSocket — accountSubscribe via Helius

`accountSubscribe` streams account state changes as they happen on-chain.
This is how you build real-time price feeds, position monitors, and sniper triggers
without polling.

## Connection pattern

```rust
use futures_util::{SinkExt, StreamExt};
use tokio_tungstenite::{connect_async, tungstenite::protocol::Message};
use serde_json::Value;

async fn account_subscribe(pubkey: &str, helius_key: &str) {
    let ws_url = format!("wss://mainnet.helius-rpc.com/?api-key={}", helius_key);

    let (ws_stream, _) = match connect_async(&ws_url).await {
        Ok(conn) => conn,
        Err(e) => {
            eprintln!("WS connect failed: {}", e);
            return;
        }
    };

    let (mut write, mut read) = ws_stream.split();

    let subscribe = serde_json::json!({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "accountSubscribe",
        "params": [
            pubkey,
            { "encoding": "base64", "commitment": "processed" }
        ]
    });

    if write.send(Message::Text(subscribe.to_string())).await.is_err() {
        return;
    }

    while let Some(msg) = read.next().await {
        match msg {
            Ok(Message::Text(text)) => {
                let parsed: Value = match serde_json::from_str(&text) {
                    Ok(v) => v,
                    Err(_) => continue,
                };

                // Skip subscription confirmation
                if parsed["method"].as_str() != Some("accountNotification") {
                    continue;
                }

                // Check lamports — zero means account was closed (rug, graduation, etc.)
                let lamports = parsed["params"]["result"]["value"]["lamports"]
                    .as_u64()
                    .unwrap_or(1);

                if lamports == 0 {
                    println!("Account closed — exiting");
                    break;
                }

                // Decode base64 account data
                if let Some(b64) = parsed["params"]["result"]["value"]["data"][0].as_str() {
                    use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
                    if let Ok(bytes) = BASE64.decode(b64) {
                        // process bytes...
                        println!("Account updated: {} bytes", bytes.len());
                    }
                }
            }
            Ok(Message::Ping(_)) | Ok(Message::Pong(_)) => continue,
            Ok(Message::Close(_)) => {
                println!("WS closed by server");
                break;
            }
            Err(e) => {
                eprintln!("WS error: {}", e);
                break;
            }
            _ => continue,
        }
    }
}
```

## Reconnect loop

Wrap the above in an outer loop for production resilience:

```rust
loop {
    account_subscribe(pubkey, &helius_key).await;
    println!("WS disconnected — reconnecting in 3s...");
    tokio::time::sleep(tokio::time::Duration::from_secs(3)).await;
}
```

## Sending updates via channel

Use a `mpsc::Sender` to decouple the WS listener from your processing logic:

```rust
use tokio::sync::mpsc;

async fn account_subscribe_sender(
    pubkey: &str,
    helius_key: &str,
    sender: mpsc::Sender<Vec<u8>>,  // sends raw account bytes
) {
    // ...same as above, but instead of println:
    if sender.is_closed() {
        return; // consumer is gone
    }
    if sender.send(bytes).await.is_err() {
        return;
    }
}
```

Dropping the sender signals the consumer the feed is done — no explicit shutdown needed.

## Commitment levels

| Level | Latency | Use case |
|-------|---------|----------|
| `processed` | Fastest (~400ms) | Sniper bots, real-time price feeds |
| `confirmed` | ~1-2s | Safer entry signals |
| `finalized` | ~13s | Settlement, accounting |

Use `processed` for latency-sensitive bots. Confirm finality separately if needed.

## jsonParsed over WebSocket

For SPL token accounts, use `jsonParsed` encoding to get decoded data:

```rust
let subscribe = serde_json::json!({
    "jsonrpc": "2.0",
    "id": 1,
    "method": "accountSubscribe",
    "params": [
        token_account_pubkey,
        { "encoding": "jsonParsed", "commitment": "processed" }
    ]
});
// parsed["params"]["result"]["value"]["data"]["parsed"]["info"]["tokenAmount"]["uiAmount"]
```
