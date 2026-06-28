# PatchToolSource — `patch-cli` 源码

这是「game client update」(hdiff/ldiff 游戏更新) 所用命令行工具 `patch-cli` 的 Go 源码。
运行时由 `Services/GameClientUpdateManager.swift` 调用：`patch-cli -game <游戏目录> -patch <补丁包>`，
通过 stdout 进度协议（`STAGE`/`PROGRESS`/`MSG`/`RESULT`）回报进度。

源码完全自包含，克隆仓库后即可修改与重建，无需任何外部目录。

## 重建

```sh
cd PatchToolSource
./build.sh
```

脚本用 Go 交叉编译 arm64 + amd64 并 `lipo` 合成 universal 二进制，输出到 `../PatchTool/patch-cli`
（即 App 实际打包的成品）。要求本机已安装 Go（`go.mod` 要求 ≥ 1.26）。

## 目录

- `cmd/patch-cli/` — 入口
- `internal/diff-service/` — hdiff / ldiff 核心逻辑
- `pkg/` — firefly 协议、hpatchz/7zz 封装、模型、校验等
- `build/` — 编译产物（被 .gitignore 忽略，不入库）

## 关于 hpatchz / 7zz

`patch-cli` 在运行时调用 `hpatchz` 与 `7zz`。这两个是 HDiffPatch / 7-Zip 的上游预编译二进制，
已作为成品提交在 `../PatchTool/`（`hpatchz_macos`、`7zz_macos`），本脚本不重建它们。
