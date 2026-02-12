# OpenClaw 客户交付方案（开箱即用）

本方案用于客户侧直接可用的 OpenClaw，不依赖 `ccman` 交互配置。

## 目标

- 只内置默认 `URL + provider + model`，不在客户端硬编码固定 API Key。
- 客户首次启动时输入 token（或由你们后端注入环境变量）。
- 自动完成三件事：写 `~/.openclaw/openclaw.json`、`gateway install/start`、健康检查。
- 只写入一个固定 provider：`Aistock`。

## 目录

- `openclaw-release/scripts/bootstrap-openclaw-windows.ps1`
- `openclaw-release/scripts/bootstrap-openclaw-macos.sh`
- `openclaw-release/scripts/bootstrap-openclaw-linux.sh`
- `openclaw-release/templates/openclaw.defaults.json`
- `openclaw-release/docs/customer-message-template.md`

## 推荐的后端发放方式

后端在客户首次激活时发放短期 token，再让客户执行脚本：

- Aistock key：`OPENCLAW_AISTOCK_API_KEY`

你们也可以不下发，改为让客户启动脚本时手工输入。

## 一键执行（客户侧）

### Windows

```powershell
powershell -ExecutionPolicy Bypass -File .\openclaw-release\scripts\bootstrap-openclaw-windows.ps1
```

### macOS

```bash
chmod +x ./openclaw-release/scripts/bootstrap-openclaw-macos.sh
./openclaw-release/scripts/bootstrap-openclaw-macos.sh
```

### Linux

```bash
chmod +x ./openclaw-release/scripts/bootstrap-openclaw-linux.sh
./openclaw-release/scripts/bootstrap-openclaw-linux.sh
```

## 可选环境变量（自动化部署）

```bash
OPENCLAW_PROVIDER_NAME=Aistock
OPENCLAW_AISTOCK_BASE_URL=https://www.aistock.tech/v1
OPENCLAW_AISTOCK_MODEL=gpt-5.3-codex
OPENCLAW_AISTOCK_API_MODE=openai-responses
OPENCLAW_AISTOCK_API_KEY=<Aistock token>
```

## 验证命令

```bash
openclaw config get agents.defaults.model.primary
openclaw config get models.providers
openclaw agent --agent main --message "请只回复OK" --json
```

健康检查失败时，脚本会打印失败输出用于定位上游报错。

## 常见问题

### 1) `Config invalid`

先修复配置再重试：

```bash
openclaw doctor --fix
```

### 2) `gateway already running` / `Port 18789 is already in use`

```bash
openclaw gateway stop
openclaw gateway start
```

### 3) `Gateway service not loaded`

```bash
openclaw gateway install
openclaw gateway start
```

### 4) macOS `uv_cwd` 错误

在一个真实存在的目录里执行（例如先 `cd ~`），不要在已删除目录内运行命令。
