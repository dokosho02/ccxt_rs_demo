# GitHub Actions 免费额度与限制（本项目视角）

> 数据来源：docs.github.com（Actions limits / runners / billing），读取日期 **2026-11-08**。
> 适用于本仓库：公开仓库 `dokosho02/ccxt_rs_demo`，5 目标远程构建。

## TL;DR

- **公开仓库 + 标准 runner：编译时长免费且不限量**（官方明确 "free and unlimited"），这是本项目用 GA 做远程构建不花钱的根基。
- 真正会撞到的墙：**并发数（20）**、**单 job 6 小时**、**artifact 存储（500 MB 池子，见下）**、**REST API 5000 次/小时**。
- 本项目一轮构建实测：约 17 分钟墙钟、5 个 artifact 共 ~125 MB、7 个并发 job（macOS 占 2）—— 免费额度完全够用。

## 1. 计算时长（分钟）

| 场景 | 规则 |
|---|---|
| **公开仓库 + 标准 runner** | **免费、不限量、不扣任何额度** |
| 私有仓库 + 标准 runner | 扣每月 included compute（Free = $12/月 ≈ 2000 Linux 分钟）；超额按分钟单价计费 |
| 更大 runner（8C/32GB+） | **公开仓库也收费**，按分钟计（Linux 4C $0.012/min、8C $0.022/min…） |
| self-hosted runner | 执行本身免费（机器钱自付） |

私有仓库分钟换算倍率：Linux 1x、Windows 2x、macOS 10x。

## 2. Runner 规格（标准档）

| 标签 | CPU | 内存 | 磁盘 | 架构 |
|---|---|---|---|---|
| `ubuntu-24.04` / `ubuntu-latest` | 4 | 16 GB | 14 GB | x64 |
| `ubuntu-24.04-arm` | 4 | 16 GB | 14 GB | **arm64** |
| `windows-latest` | 4 | 16 GB | 14 GB | x64 |
| `macos-15-intel` | 4 | 14 GB | 14 GB | x64 |
| `macos-latest`（arm64） | 3 | **7 GB** | 14 GB | arm64 |

注意：

- 私有仓库同标签只有 **2C/8GB**（公开仓库才给 4C/16GB）。
- **`ubuntu-latest` 永远不会解析到 arm64**，arm 只有显式 `ubuntu-XX.XX-arm` 标签。
- `macos-latest` 只有 7GB 内存，所以本项目 macOS 双目标都放在 `macos-15-intel`（14GB）。
- 磁盘统一 14 GB —— ccxt 全量 features（release ~50GB 峰值内存）放标准 runner 会 OOM/爆盘，这就是只编 12 个交易所的原因。

## 3. 并发限制

| 计划 | 总并发 job | 其中 macOS 并发 |
|---|---|---|
| **Free** | **20** | 5 |
| Pro | 40 | 5 |
| Team | 60 | 5 |
| Enterprise | 500 | 50 |

本项目一轮 = 1 lint + 1 prepare + 5 build = 7 个 job（macOS 2 个），远低于上限。多分支同时跑也不会有压力。

## 4. 时长与规模限制

| 项目 | 限制 |
|---|---|
| 单 job 执行 | **6 小时**（超出即失败） |
| 单次 workflow run | 35 天 |
| matrix 展开 | 256 个 job / run |
| 同一 run 重跑 | 50 次 |
| 触发事件速率 | 1500 次 / 10 秒 / 仓库 |
| 排队中的 run | 500 个 / 10 秒 |
| workflow 文件大小 | 500 KB |
| `workflow_dispatch` inputs | 25 个顶层字段、payload ≤ 65,535 字符 |
| `workflow_dispatch` 触发点 | **只能从默认分支**（`gh workflow run --ref` 必须指向 main 上的 workflow 文件） |

## 5. 存储

| 类型 | 额度 | 超额单价 |
|---|---|---|
| **Artifact** | 按计划池子：Free **500 MB**（与 GitHub Packages 共享） | $0.25 / GB / 月（按小时累计 GB·小时） |
| **Cache** | **10 GB / 仓库**（独立，不与 artifact 混用） | $0.07 / GB / 月（按每小时峰值） |
| 日志 / job summary | 不计入存储 | — |

Artifact 相关规则：

- **保留期**：默认 90 天；**公开仓库只能设 1–90 天**（本项目设 30 天）；到期硬删除、不可恢复。
- 每个 job 最多 500 个 artifact；本项目每轮 5 个、共约 **125 MB**（单个 22–26 MB 压缩后）。
- ⚠️ **文档歧义（2026-11 实况）**：官方计费文档只写明"公开仓库标准 runner 免费"，artifact 是否豁免 500 MB 池子说法不一 —— 有第三方实测称公开仓库不计，也有 2026-10 公开仓库撞 artifact 配额的报告。**按保守假设管理**：30 天保留期内如果反复构建（每轮 ~125 MB），几轮滚动就可能接近 500 MB。控制手段：
  - 缩短 `retention-days`（本项目 30 → 可再降）；
  - 只在需要时手动下载后删 artifact（`DELETE /repos/{o}/{r}/actions/artifacts/{id}` 或网页删除）；
  - 或改用 Release 存档（公开仓库 Release 存储不占这个池子，但会永久留存，注意仓库体积）。
- Cache 10 GB/仓库对本项目绰绰有余（rust-cache 一套 target 缓存 ~1–2 GB/目标），超了也只是最旧的被 LRU 淘汰（cache 本身还有 7 天未访问淘汰策略）。

Cache API 速率：上传 200 次/分、下载 1500 次/分、删除 400 次/分（每仓库）。

## 6. REST API（`just build-remote` 轮询脚本相关）

| 项目 | 限制 |
|---|---|
| 认证请求 | **5000 次 / 小时 / 用户**（justfile 里 3 秒一轮的 run 发现循环 × 下载 5 个 artifact，占用可忽略） |
| artifact 匿名下载 | 不带 token 返回 401，必须认证（git credential / gh 均可） |

## 7. 本项目实测（run 42434147353，2026-11-08，冷缓存）

| Job | 结果 | 时长 |
|---|---|---|
| prepare matrix | ✅ | 0.1 min |
| validate (ubuntu, fmt+clippy+check) | ✅ | 1.0 min |
| build x86_64-unknown-linux-gnu | ✅ | 7.4 min |
| build aarch64-unknown-linux-gnu | ✅ | 5.1 min |
| build x86_64-pc-windows-msvc | ✅ | 10.9 min |
| build x86_64-apple-darwin | ✅ | 12.1 min |
| build aarch64-apple-darwin（交叉） | ✅ | 15.5 min |

- 墙钟总时长 ≈ 17 分钟（5 个 build 并行，最慢者决定）。
- 产物：5 × 22–26 MB artifact，保留 30 天。
- 免费账单：**$0**（全部落在公开仓库标准 runner 免费区间）。

## 8. 参考链接

- 限制总表：<https://docs.github.com/en/actions/reference/limits>
- Runner 规格：<https://docs.github.com/en/actions/reference/runners/github-hosted-runners>
- 计费概念：<https://docs.github.com/en/billing/concepts/product-billing/github-actions>
- 定价（更大 runner 单价）：<https://docs.github.com/en/billing/reference/actions-runner-pricing>
