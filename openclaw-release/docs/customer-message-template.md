# 客户发送模板（可直接复制）

下面三份文案可直接发给客户（微信/邮件/工单）。

## 模板 A：首次开通（通用）

你好，已为你开通 OpenClaw 服务。请按下面步骤操作：

1. 先安装最新版 `openclaw` 与 `Node.js 18+`
2. 执行我们的一键初始化脚本（会自动写配置、启动网关、做连通性检查）
3. 首次执行时输入你的 API Token（不会硬编码在客户端）

执行命令（按你的系统选择）：

- Windows
  - `iwr https://raw.githubusercontent.com/Yho0/openclaw-codexcli/main/openclaw-release/scripts/bootstrap-openclaw-windows.ps1 -OutFile .\bootstrap-openclaw-windows.ps1`
  - `powershell -ExecutionPolicy Bypass -File .\bootstrap-openclaw-windows.ps1`
- macOS
  - `curl -fsSL https://raw.githubusercontent.com/Yho0/openclaw-codexcli/main/openclaw-release/scripts/bootstrap-openclaw-macos.sh | bash`
- Linux
  - `curl -fsSL https://raw.githubusercontent.com/Yho0/openclaw-codexcli/main/openclaw-release/scripts/bootstrap-openclaw-linux.sh | bash`

验证是否成功：

- `openclaw config get agents.defaults.model.primary`
- `openclaw agent --agent main --message "请只回复OK" --json`

---

## 模板 B：快速排障（客户报错时）

请按顺序执行以下命令并把输出发我：

1. `openclaw doctor --fix`
2. `openclaw gateway stop`
3. `openclaw gateway install`
4. `openclaw gateway start`
5. `openclaw agent --agent main --message "请只回复OK" --json`

如果仍失败，请再补充：

- `openclaw config get agents.defaults.model.primary`
- `openclaw config get models.providers`

---

## 模板 C：升级到我们的发行版

请执行：

- `npm install -g https://github.com/Yho0/openclaw-codexcli/releases/download/v3.3.4-openclaw/ccman-3.3.4.tgz --force`

升级后再次运行一键初始化脚本（会自动覆盖为最新默认配置）。

