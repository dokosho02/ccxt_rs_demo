use ccxt::{Params, TypedExchangeExt};

const EXCHANGES: &[&str] = &[
    "binance",
    "okx",
    "kraken",
    "bitget",
    "bybit",
    "coinbase",
    "xt",
    "htx",
    "gate",
    "bitfinex",
    "kucoin",
    "hyperliquid",
];

const USAGE: &str = "ccxt_demo — ccxt Rust demo

USAGE:
    ccxt_demo [--version] [--exchange <id>] [symbol]

ARGS:
    [symbol]           Market symbol to fetch (default: BTC/USDT)
    --exchange <id>    Exchange to use (default: binance)
    --version          Print version/target info and exit (no network)
    --help             Print this help
";

fn main() {
    // The transpiled core panics across an internal catch_unwind; silence the
    // default hook unless CCXT_SHOW_PANICS=1 (see ccxt rust docs).
    if std::env::var("CCXT_SHOW_PANICS").is_err() {
        std::panic::set_hook(Box::new(|_| {}));
    }

    let args: Vec<String> = std::env::args().skip(1).collect();

    if args.iter().any(|a| a == "--help") {
        print!("{USAGE}");
        return;
    }
    if args.iter().any(|a| a == "--version") {
        println!(
            "ccxt_demo {} ({}/{})",
            env!("CARGO_PKG_VERSION"),
            std::env::consts::ARCH,
            std::env::consts::OS
        );
        return;
    }

    let mut exchange_id = "binance".to_string();
    let mut symbol = "BTC/USDT".to_string();
    let mut it = args.into_iter();
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "--exchange" => {
                exchange_id = it.next().unwrap_or_else(|| "binance".to_string());
            }
            s if s.starts_with("--") => {
                eprintln!("unknown flag: {s}\n\n{USAGE}");
                std::process::exit(2);
            }
            s => symbol = s.to_string(),
        }
    }

    // Worker threads need a large stack: the generated exchange code is deeply
    // nested and the default 2 MB can overflow (see ccxt rust docs).
    let rt = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .thread_stack_size(64 * 1024 * 1024)
        .enable_all()
        .build()
        .expect("failed to build tokio runtime");

    rt.block_on(async move {
        if let Err(e) = run(&exchange_id, &symbol).await {
            eprintln!("error: {e}");
            std::process::exit(1);
        }
    });
}

async fn run(exchange_id: &str, symbol: &str) -> Result<(), String> {
    let mut exchange = ccxt::from_id(exchange_id, None).ok_or_else(|| {
        format!(
            "unknown or not-compiled exchange '{exchange_id}' (compiled: {})",
            EXCHANGES.join(", ")
        )
    })?;
    exchange.load_markets(false).await;
    if exchange.markets().is_empty() {
        return Err("failed to load markets (network error?)".to_string());
    }
    let ticker = exchange
        .fetch_ticker(symbol, Params::none())
        .await
        .map_err(|e| e.to_string())?;
    println!(
        "{} last={:?} bid={:?} ask={:?}",
        ticker.symbol, ticker.last, ticker.bid, ticker.ask
    );
    Ok(())
}
