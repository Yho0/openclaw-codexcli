Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location $HOME

if (-not (Get-Command openclaw -ErrorAction SilentlyContinue)) {
  Write-Error "openclaw was not found. Install openclaw first."
  exit 1
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Error "node was not found. Install Node.js 18+ first."
  exit 1
}

$primaryProvider = if ($env:OPENCLAW_PRIMARY_PROVIDER) { $env:OPENCLAW_PRIMARY_PROVIDER } else { 'primary' }
$primaryBaseUrl = if ($env:OPENCLAW_PRIMARY_BASE_URL) { $env:OPENCLAW_PRIMARY_BASE_URL } else { 'https://www.aistock.tech/v1' }
$primaryModel = if ($env:OPENCLAW_PRIMARY_MODEL) { $env:OPENCLAW_PRIMARY_MODEL } else { 'gpt-5.3-codex' }
$primaryApi = if ($env:OPENCLAW_PRIMARY_API) { $env:OPENCLAW_PRIMARY_API } else { 'openai-responses' }

$backupProvider = if ($env:OPENCLAW_BACKUP_PROVIDER) { $env:OPENCLAW_BACKUP_PROVIDER } else { 'backup' }
$backupBaseUrl = if ($env:OPENCLAW_BACKUP_BASE_URL) { $env:OPENCLAW_BACKUP_BASE_URL } else { 'https://cdn.12ai.org/v1' }
$backupModel = if ($env:OPENCLAW_BACKUP_MODEL) { $env:OPENCLAW_BACKUP_MODEL } else { 'gpt-5.3-codex' }
$backupApi = if ($env:OPENCLAW_BACKUP_API) { $env:OPENCLAW_BACKUP_API } else { 'openai-completions' }

$primaryApiKey = $env:OPENCLAW_PRIMARY_API_KEY
$backupApiKey = $env:OPENCLAW_BACKUP_API_KEY

if ([string]::IsNullOrWhiteSpace($primaryApiKey)) {
  $secure = Read-Host "Enter primary API key" -AsSecureString
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    $primaryApiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
  }
}

if ([string]::IsNullOrWhiteSpace($primaryApiKey)) {
  Write-Error "Primary API key is required."
  exit 1
}

if ([string]::IsNullOrWhiteSpace($backupApiKey)) {
  $secure = Read-Host "Enter backup API key (press Enter to reuse primary)" -AsSecureString
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    $backupApiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
  }
}

if ([string]::IsNullOrWhiteSpace($backupApiKey)) {
  $backupApiKey = $primaryApiKey
}

$configDir = Join-Path $HOME ".openclaw"
$configFile = Join-Path $configDir "openclaw.json"
New-Item -ItemType Directory -Path $configDir -Force | Out-Null

if (Test-Path $configFile) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  Copy-Item $configFile "$configFile.bak.$stamp" -Force
}

$env:OPENCLAW_CONFIG_FILE = $configFile
$env:OPENCLAW_PRIMARY_PROVIDER = $primaryProvider
$env:OPENCLAW_PRIMARY_BASE_URL = $primaryBaseUrl
$env:OPENCLAW_PRIMARY_MODEL = $primaryModel
$env:OPENCLAW_PRIMARY_API = $primaryApi
$env:OPENCLAW_PRIMARY_API_KEY = $primaryApiKey
$env:OPENCLAW_BACKUP_PROVIDER = $backupProvider
$env:OPENCLAW_BACKUP_BASE_URL = $backupBaseUrl
$env:OPENCLAW_BACKUP_MODEL = $backupModel
$env:OPENCLAW_BACKUP_API = $backupApi
$env:OPENCLAW_BACKUP_API_KEY = $backupApiKey

$writeScript = @'
const fs = require("fs");
const configFile = process.env.OPENCLAW_CONFIG_FILE;
const primaryProvider = process.env.OPENCLAW_PRIMARY_PROVIDER;
const primaryBaseUrl = process.env.OPENCLAW_PRIMARY_BASE_URL;
const primaryModel = process.env.OPENCLAW_PRIMARY_MODEL;
const primaryApi = process.env.OPENCLAW_PRIMARY_API;
const primaryApiKey = process.env.OPENCLAW_PRIMARY_API_KEY;
const backupProvider = process.env.OPENCLAW_BACKUP_PROVIDER;
const backupBaseUrl = process.env.OPENCLAW_BACKUP_BASE_URL;
const backupModel = process.env.OPENCLAW_BACKUP_MODEL;
const backupApi = process.env.OPENCLAW_BACKUP_API;
const backupApiKey = process.env.OPENCLAW_BACKUP_API_KEY;

const modelRecord = (model) => ({
  id: model,
  name: model,
  reasoning: false,
  input: ["text"],
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
  contextWindow: 200000,
  maxTokens: 8192
});

const providerRecord = ({ baseUrl, apiKey, api, model }) => ({
  baseUrl,
  apiKey,
  api,
  headers: {
    "User-Agent": "codex_cli_rs/0.98.0",
    "x-stainless-lang": "rust",
    "x-stainless-runtime": "rust",
    "x-stainless-runtime-version": "0.98.0",
    "x-stainless-package-version": "0.98.0"
  },
  models: [modelRecord(model)]
});

let config = {};
if (fs.existsSync(configFile)) {
  const raw = fs.readFileSync(configFile, "utf8").trim();
  if (raw) config = JSON.parse(raw);
}

config.models = config.models || {};
config.models.providers = config.models.providers || {};
config.models.providers[primaryProvider] = providerRecord({
  baseUrl: primaryBaseUrl,
  apiKey: primaryApiKey,
  api: primaryApi,
  model: primaryModel
});
config.models.providers[backupProvider] = providerRecord({
  baseUrl: backupBaseUrl,
  apiKey: backupApiKey,
  api: backupApi,
  model: backupModel
});

config.agents = config.agents || {};
config.agents.defaults = config.agents.defaults || {};
config.agents.defaults.model = config.agents.defaults.model || {};
config.agents.defaults.model.primary = `${primaryProvider}/${primaryModel}`;

fs.writeFileSync(configFile, JSON.stringify(config, null, 2) + "\n");
'@
node -e $writeScript
node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));' $configFile
Write-Host "openclaw.json written to $configFile"

try {
  openclaw gateway restart *> $null
} catch {
  try { openclaw gateway install *> $null } catch {}
  try { openclaw gateway start *> $null } catch {}
}

function Test-OpenClawHealth {
  $tmp = New-TemporaryFile
  try {
    openclaw agent --agent main --message "Please reply OK only" --json *> $tmp.FullName
    $content = Get-Content -Path $tmp.FullName -Raw -ErrorAction SilentlyContinue
    if ($content -match 'OK') {
      return $true
    }
  } catch {
  } finally {
    Remove-Item $tmp.FullName -Force -ErrorAction SilentlyContinue
  }
  return $false
}

if (Test-OpenClawHealth) {
  Write-Host "Health check passed on $primaryProvider/$primaryModel"
  exit 0
}

Write-Host "Primary failed, switching to backup provider..."
$env:OPENCLAW_CONFIG_FILE = $configFile
$env:OPENCLAW_BACKUP_PROVIDER = $backupProvider
$env:OPENCLAW_BACKUP_MODEL = $backupModel

$switchScript = @'
const fs = require("fs");
const file = process.env.OPENCLAW_CONFIG_FILE;
const provider = process.env.OPENCLAW_BACKUP_PROVIDER;
const model = process.env.OPENCLAW_BACKUP_MODEL;
const data = JSON.parse(fs.readFileSync(file, "utf8"));
data.agents = data.agents || {};
data.agents.defaults = data.agents.defaults || {};
data.agents.defaults.model = data.agents.defaults.model || {};
data.agents.defaults.model.primary = `${provider}/${model}`;
fs.writeFileSync(file, JSON.stringify(data, null, 2) + "\n");
'@
node -e $switchScript

if (Test-OpenClawHealth) {
  Write-Host "Health check passed on $backupProvider/$backupModel"
  exit 0
}

Write-Error "Both primary and backup providers failed health checks."
exit 1
