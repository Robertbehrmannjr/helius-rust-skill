# Circuit Breaker — Handling Helius 429s in Production

Helius rate limits are enforced per API key. In a trading bot, a 429 during a buy means
your security checks are blind — the right move is to block new trades until the API recovers,
not to proceed unverified.

This is a lock-free circuit breaker using atomics. It's `const`-constructible so it works
as a `static`, and it auto-resets after a cooldown without any background task.

## Implementation

```rust
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

const COOLDOWN_SECS: u64 = 60;

pub struct CircuitBreaker {
    open: AtomicBool,
    last_trip_secs: AtomicU64,
}

impl CircuitBreaker {
    pub const fn new() -> Self {
        Self {
            open: AtomicBool::new(false),
            last_trip_secs: AtomicU64::new(0),
        }
    }

    /// Call on any 429 response from Helius.
    pub fn trip(&self) {
        self.last_trip_secs.store(now_unix(), Ordering::Relaxed);
        // compare_exchange ensures only the first trip logs — avoids log spam
        if self.open
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
            .is_ok()
        {
            eprintln!(
                "[CIRCUIT BREAKER] Helius rate limited — blocking for {}s",
                COOLDOWN_SECS
            );
        }
    }

    /// Returns true if the breaker is open (API degraded).
    /// Auto-resets after COOLDOWN_SECS — no background task needed.
    pub fn is_open(&self) -> bool {
        if !self.open.load(Ordering::SeqCst) {
            return false;
        }
        let elapsed = now_unix()
            .saturating_sub(self.last_trip_secs.load(Ordering::Relaxed));
        if elapsed >= COOLDOWN_SECS {
            if self.open
                .compare_exchange(true, false, Ordering::SeqCst, Ordering::SeqCst)
                .is_ok()
            {
                println!("[CIRCUIT BREAKER] Helius recovered — resuming");
            }
            return false;
        }
        true
    }
}

fn now_unix() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

// Declare as a global static — const fn makes this zero-cost
pub static HELIUS: CircuitBreaker = CircuitBreaker::new();
```

## Usage

Trip on 429:

```rust
let resp = client.post(&rpc_url).json(&body).send().await?;
if resp.status() == reqwest::StatusCode::TOO_MANY_REQUESTS {
    crate::circuit_breaker::HELIUS.trip();
    return Err("429".to_string());
}
```

Guard before any action that requires a verified security check:

```rust
if HELIUS.is_open() {
    return Err("Helius degraded — skipping".into());
}
```

## Design notes

- **Lock-free**: uses `AtomicBool` + `AtomicU64`, safe to check from any async task
- **Auto-reset**: `is_open()` checks elapsed time and resets — no timer task, no Mutex
- **`const fn new()`**: enables `static` declaration with zero initialization overhead
- **compare_exchange on trip**: deduplicate log spam when 429s cascade across parallel calls
- **60s cooldown**: conservative default; tune to your request budget

## Multiple breakers

If you use multiple external APIs, declare one breaker per service:

```rust
pub static HELIUS: CircuitBreaker = CircuitBreaker::new();
pub static JUPITER: CircuitBreaker = CircuitBreaker::new();
pub static PUMPFUN: CircuitBreaker = CircuitBreaker::new();
```
