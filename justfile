# ccxt_rs_demo — 项目管理入口（just <recipe>）
# 本地重活（编译/冒烟）请走 GitHub Actions：just build-remote / just download

set shell := ["bash", "-euo", "pipefail", "-c"]

# 覆盖的全部构建目标
targets := "x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu x86_64-pc-windows-msvc x86_64-apple-darwin aarch64-apple-darwin"
workflow := "build.yml"
bin := "ccxt_demo"

# 列出所有 recipe
default:
    @just --list

# ---------------------------------------------------------------- 本地（轻量）

# 本地 release 构建（内存紧张的机器请用 just build-remote）
build:
    cargo build --release

# 本地运行：just run -- --exchange kraken BTC/USDT
run *ARGS:
    cargo run --release -- {{ARGS}}

# 类型检查（比 build 轻量得多）
check:
    cargo check --all-targets

# 静态检查
clippy:
    cargo clippy --all-targets -- -D warnings

fmt:
    cargo fmt --all

fmt-check:
    cargo fmt --all -- --check

# CI 本地等价物：格式 + 静态检查（不产出二进制）
ci: fmt-check clippy

# ---------------------------------------------------------------- 远程（GA）

# 触发 GA 全量构建，等待完成后自动下载产物到 target/remote/<triple>/
build-remote:
    #!/usr/bin/env bash
    set -euo pipefail
    command -v gh >/dev/null || { echo "error: 需要 GitHub CLI（gh）。安装：brew install gh 或 apt install gh" >&2; exit 1; }
    branch="$(git symbolic-ref --short HEAD)"
    before="$(gh run list --workflow={{workflow}} --limit 1 --json databaseId --jq '.[0].databaseId // 0')"
    echo "触发 {{workflow}} @ ${branch} ..."
    gh workflow run {{workflow}} --ref "${branch}"
    run_id=0
    for _ in $(seq 1 30); do
        sleep 3
        run_id="$(gh run list --workflow={{workflow}} --branch "${branch}" --limit 1 --json databaseId --jq '.[0].databaseId // 0')"
        [[ "${run_id}" != "0" && "${run_id}" != "${before}" ]] && break
        run_id=0
    done
    if [[ "${run_id}" == "0" ]]; then
        echo "error: 等待 run 出现超时（gh run list --workflow={{workflow}}）" >&2
        exit 1
    fi
    echo "run: ${run_id} — gh run watch ${run_id}"
    gh run watch "${run_id}" --exit-status --interval 15
    just download "${run_id}"

# 下载某次 run 的产物到 target/remote/<triple>/（缺产物的目标会跳过）
download run_id="":
    #!/usr/bin/env bash
    set -euo pipefail
    command -v gh >/dev/null || { echo "error: 需要 GitHub CLI（gh）。安装：brew install gh 或 apt install gh" >&2; exit 1; }
    rid="{{run_id}}"
    if [[ -z "${rid}" ]]; then
        rid="$(gh run list --workflow={{workflow}} --limit 1 --json databaseId,conclusion --jq '.[0].databaseId')"
    fi
    if [[ -z "${rid}" || "${rid}" == "null" ]]; then
        echo "error: 没有找到 run" >&2
        exit 1
    fi
    echo "下载 run ${rid} 的产物 ..."
    fail=0
    for t in {{targets}}; do
        dest="target/remote/${t}"
        mkdir -p "${dest}"
        if gh run download "${rid}" --name "ccxt_demo-${t}" --dir "${dest}" 2>/dev/null; then
            chmod +x "${dest}/ccxt_demo" 2>/dev/null || true
            echo "  ok   ${t} -> ${dest}/"
        else
            echo "  skip ${t}（无产物：该目标构建失败或被过滤）" >&2
            fail=1
        fi
    done
    [[ "${fail}" == "0" ]] || echo "warning: 部分目标缺少产物" >&2
    ls -l target/remote/*/ccxt_demo* 2>/dev/null || true

# 列出最近的构建 run
runs:
    gh run list --workflow={{workflow}} --limit 10

# 清理本地构建
clean:
    cargo clean
    rm -rf target/remote
