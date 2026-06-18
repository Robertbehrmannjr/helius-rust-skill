# Rules — Helius + Rust

When helping with Helius + Rust code, follow these production-tested conventions:

## RPC calls

- Always use `reqwest` directly for JSON-RPC calls — faster and more flexible than `solana-client` for HTTP
- Wrap `solana-client::RpcClient` calls in `tokio::task::spawn_blocking` — it is synchronous
- Set a hard timeout of 4-5s on all HTTP requests — Helius can hang under load
- Check `resp.status() == TOO_MANY_REQUESTS` before `.json()` — don't try to parse 429 bodies
- Trip the circuit breaker on every 429 response
- Use `CommitmentConfig::processed()` for latency-sensitive paths

## WebSocket

- Prefer `accountSubscribe` over polling for anything real-time
- Always handle `Ping`, `Pong`, `Close`, and `Err` variants explicitly — don't just match `Text`
- Check `sender.is_closed()` at the top of each message loop iteration — avoid wasted work
- Return the `mpsc::Sender` on WS failure so the caller can hand it to a REST fallback
- Dropping the sender is the correct shutdown signal — don't add an explicit close message

## Circuit breaker

- Declare as `pub static BREAKER: CircuitBreaker = CircuitBreaker::new()` — one per external API
- Guard any action that requires Helius data with `if BREAKER.is_open() { return Err(...) }`
- In live trading mode, block on degraded API — never act on unverified data

## Parallelism

- Use `tokio::join!` when you need multiple RPC checks before an action — cuts latency in half
- If ALL parallel checks fail, treat it as API degradation, not individual errors

## Error handling

- Return `Err(String)` from low-level RPC helpers — simpler than custom error types for internal code
- Never `.unwrap()` on RPC responses — network calls fail in production
- Log 429s and connection failures at `eprintln!` level, not `panic!`
