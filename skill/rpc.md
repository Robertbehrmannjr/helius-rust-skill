# RPC — Helius JSON-RPC in Rust

All calls use `reqwest` directly against the Helius HTTP endpoint.
Always check for 429 and trip the circuit breaker — see [circuit-breaker.md](circuit-breaker.md).

## getAccountInfo (jsonParsed)

Use `jsonParsed` to get decoded SPL token accounts without borsh:

```rust
async fn get_account_info(
    mint: &str,
    helius_key: &str,
) -> Result<serde_json::Value, String> {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(4))
        .build()
        .unwrap();

    let body = serde_json::json!({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "getAccountInfo",
        "params": [ mint, { "encoding": "jsonParsed" } ]
    });

    let resp = client
        .post(format!("https://mainnet.helius-rpc.com/?api-key={}", helius_key))
        .json(&body)
        .send()
        .await
        .map_err(|e| e.to_string())?;

    if resp.status() == reqwest::StatusCode::TOO_MANY_REQUESTS {
        // trip circuit breaker here
        return Err("429".to_string());
    }

    resp.json::<serde_json::Value>().await.map_err(|e| e.to_string())
}
```

### Check freeze authority on an SPL mint

```rust
let data = get_account_info(mint, &helius_key).await?;
let freeze_auth = data["result"]["value"]["data"]["parsed"]["info"]["freezeAuthority"]
    .as_str();

let has_freeze = freeze_auth.is_some() && !freeze_auth.unwrap().is_empty();
```

### Read raw account bytes (base64)

```rust
let body = serde_json::json!({
    "jsonrpc": "2.0",
    "id": 1,
    "method": "getAccountInfo",
    "params": [ pubkey, { "encoding": "base64" } ]
});
// data["result"]["value"]["data"][0] is the base64 string
```

## getSignaturesForAddress

Used to check wallet history — e.g. detect fresh rug wallets:

```rust
async fn get_signature_count(
    wallet: &str,
    limit: u64,
    helius_key: &str,
) -> Result<usize, String> {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(4))
        .build()
        .unwrap();

    let body = serde_json::json!({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "getSignaturesForAddress",
        "params": [ wallet, { "limit": limit } ]
    });

    let resp = client
        .post(format!("https://mainnet.helius-rpc.com/?api-key={}", helius_key))
        .json(&body)
        .send()
        .await
        .map_err(|e| e.to_string())?;

    if resp.status() == reqwest::StatusCode::TOO_MANY_REQUESTS {
        return Err("429".to_string());
    }

    let data: serde_json::Value = resp.json().await.map_err(|e| e.to_string())?;
    Ok(data["result"].as_array().map(|a| a.len()).unwrap_or(0))
}
```

## Parallel checks with tokio::join!

```rust
let (freeze_result, wallet_result) = tokio::join!(
    check_freeze_authority(mint, &helius_key),
    check_wallet_history(dev_wallet, &helius_key)
);
```

Parallel calls cut latency roughly in half when you need multiple RPC checks before acting.

## Degraded-API guard

In live trading mode, block action if all checks fail (API is down):

```rust
if mode == "live" && freeze_result.is_err() && wallet_result.is_err() {
    // Both Helius checks failed — API degraded, block the trade
    return Err("Helius unavailable — security unverified".into());
}
```
