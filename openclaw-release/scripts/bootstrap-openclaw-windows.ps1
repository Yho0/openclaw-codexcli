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

$providerName = if ($env:OPENCLAW_PROVIDER_NAME) { $env:OPENCLAW_PROVIDER_NAME } else { 'Aistock' }
$baseUrl = if ($env:OPENCLAW_AISTOCK_BASE_URL) { $env:OPENCLAW_AISTOCK_BASE_URL } else { 'https://www.aistock.tech/v1' }
$modelName = if ($env:OPENCLAW_AISTOCK_MODEL) { $env:OPENCLAW_AISTOCK_MODEL } else { 'gpt-5.3-codex' }
$apiMode = if ($env:OPENCLAW_AISTOCK_API_MODE) { $env:OPENCLAW_AISTOCK_API_MODE } else { 'openai-responses' }
$apiKey = if ($env:OPENCLAW_AISTOCK_API_KEY) { $env:OPENCLAW_AISTOCK_API_KEY } else { $env:OPENCLAW_PRIMARY_API_KEY }

if ([string]::IsNullOrWhiteSpace($apiKey)) {
  $secure = Read-Host "Enter Aistock API key" -AsSecureString
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    $apiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
  }
}

if ([string]::IsNullOrWhiteSpace($apiKey)) {
  Write-Error "Aistock API key is required."
  exit 1
}

$configDir = Join-Path $HOME ".openclaw"
$configFile = Join-Path $configDir "openclaw.json"
New-Item -ItemType Directory -Path $configDir -Force | Out-Null

if (Test-Path $configFile) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  Copy-Item $configFile "$configFile.bak.$stamp" -Force
}

$env:OPENCLAW_CONFIG_FILE = $configFile
$env:OPENCLAW_PROVIDER_NAME = $providerName
$env:OPENCLAW_AISTOCK_BASE_URL = $baseUrl
$env:OPENCLAW_AISTOCK_MODEL = $modelName
$env:OPENCLAW_AISTOCK_API_MODE = $apiMode
$env:OPENCLAW_AISTOCK_API_KEY = $apiKey

$writeScript = @'
const fs = require("fs");
const configFile = process.env.OPENCLAW_CONFIG_FILE;
const providerName = process.env.OPENCLAW_PROVIDER_NAME;
const baseUrl = process.env.OPENCLAW_AISTOCK_BASE_URL;
const modelName = process.env.OPENCLAW_AISTOCK_MODEL;
const apiMode = process.env.OPENCLAW_AISTOCK_API_MODE;
const apiKey = process.env.OPENCLAW_AISTOCK_API_KEY;

let config = {};
if (fs.existsSync(configFile)) {
  const raw = fs.readFileSync(configFile, "utf8").trim();
  if (raw) config = JSON.parse(raw);
}

config.models = config.models || {};
config.models.providers = config.models.providers || {};
config.models.providers[providerName] = {
  baseUrl,
  apiKey,
  api: apiMode,
  headers: {
    "User-Agent": "codex_cli_rs/0.98.0",
    "x-stainless-lang": "rust",
    "x-stainless-runtime": "rust",
    "x-stainless-runtime-version": "0.98.0",
    "x-stainless-package-version": "0.98.0"
  },
  models: [
    {
      id: modelName,
      name: modelName
    }
  ]
};

config.agents = config.agents || {};
config.agents.defaults = config.agents.defaults || {};
config.agents.defaults.model = config.agents.defaults.model || {};
config.agents.defaults.model.primary = `${providerName}/${modelName}`;

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

$tmp = New-TemporaryFile
try {
  openclaw agent --agent main --message "Please reply OK only" --json *> $tmp.FullName
  $content = Get-Content -Path $tmp.FullName -Raw -ErrorAction SilentlyContinue
  if ($content -match 'OK') {
    Write-Host "Health check passed on $providerName/$modelName"
    exit 0
  }
  Write-Host $content
} catch {
  Write-Host $_
} finally {
  Remove-Item $tmp.FullName -Force -ErrorAction SilentlyContinue
}

Write-Error "Health check failed on $providerName/$modelName."
exit 1
