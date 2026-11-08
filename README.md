# ccxt_rs_demo

用 [ccxt (Rust)](https://crates.io/crates/ccxt) 写的最小 demo，编译（含多平台交叉编译）全部交给 **GitHub Actions**，产物下载回本地 `target/remote/`。

本机内存不够跑全量 release 编译，所以设计为：**本地只做轻量检查，重活全在 GA 上跑**。

## 目标矩阵

| Target | Runner | 说明 |
|---|---|---|
| `x86_64-unknown-linux-gnu` | `ubuntu-24.04` | 原生 |
| `aarch64-unknown-linux-gnu` | `ubuntu-24.04-arm` | 原生 arm64（公开仓库免费） |
| `x86_64-pc-windows-msvc` | `windows-latest` | 原生 |
| `x86_64-apple-darwin` | `macos-15-intel` | 原生 Intel |
| `aarch64-apple-darwin` | `macos-15-intel` | **交叉编译**（macos-latest 只有 7GB 内存，Intel runner 有 14GB） |

验证（fmt / clippy / debug build / 冒烟）在 `ubuntu-latest` 的 `validate` job 里做，通过后才跑 release 矩阵。

## 用法

```sh
just                # 列出所有命令
just build-remote   # 触发 GA 构建 → 等待完成 → 下载产物到 target/remote/
just download       # 只下载最近一次 run 的产物
just runs           # 查看最近的构建记录
```

产物布局：

```
target/remote/
├── x86_64-unknown-linux-gnu/ccxt_demo
├── aarch64-unknown-linux-gnu/ccxt_demo
├── x86_64-pc-windows-msvc/ccxt_demo.exe
├── x86_64-apple-darwin/ccxt_demo
└── aarch64-apple-darwin/ccxt_demo
```

artifact 保留 30 天。需要 `gh` CLI：`brew install gh` / `apt install gh`。

只构建部分目标：Actions 页面手动 dispatch 并填 `targets`（逗号分隔），或

```sh
gh workflow run build.yml -f targets=x86_64-unknown-linux-gnu,aarch64-apple-darwin
just download
```

## 本地命令（轻量）

```sh
just check      # cargo check
just fmt        # 格式化
just ci         # fmt --check + clippy（等价于 GA validate）
just run -- --exchange kraken BTC/USDT   # 本地跑（需要 release 编译，内存要够）
```

## Demo 本身

```sh
./target/remote/x86_64-unknown-linux-gnu/ccxt_demo --version
./target/remote/x86_64-unknown-linux-gnu/ccxt_demo --exchange binance BTC/USDT
./target/remote/x86_64-unknown-linux-gnu/ccxt_demo --help
```

编译进去的交易所（`Cargo.toml` 的 ccxt features，可自行增删）：

`binance` `okx` `kraken` `bitget` `bybit` `coinbase` `xt` `htx` `gate` `bitfinex` `kucoin` `hyperliquid`

> 注意：feature 名是 `gate` 而不是 `gateio`（ccxt 官方 id 就叫 `gate`）。

## 为什么不用默认的 all features

ccxt 默认编译全部 100+ 交易所：debug 峰值 ~19GB 内存、release ~50GB，且磁盘 14GB 的 GA 标准 runner 会直接 OOM/爆盘。只编译需要的交易所后，编译时间与内存都是可接受的量级。
