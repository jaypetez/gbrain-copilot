# install-copilot.ps1 — set up gbrain for GitHub Copilot CLI on Windows.
#
# Installs Bun if missing, installs gbrain from this fork, runs schema
# migrations, creates a local PGLite brain, and merges the gbrain MCP server
# entry into Copilot CLI's mcp-config.json (preserving existing servers).
#
# Usage (from a clone):    .\scripts\install-copilot.ps1 [-Yes] [-CopySkills] [-SkipInit]
# Usage (one-liner):       irm https://raw.githubusercontent.com/jaypetez/gbrain-copilot/main/scripts/install-copilot.ps1 | iex
#
#   -Yes         Non-interactive: accept prompts, replace an existing gbrain
#                MCP entry if present.
#   -CopySkills  Also copy the bundled skills to ~/.copilot/skills/ (skip if
#                you plan to install the plugin via `/plugin marketplace add
#                jaypetez/gbrain-copilot` + `/plugin install gbrain@gbrain-copilot`,
#                which ships them — using both duplicates skill names).
#   -SkipInit    Skip `gbrain init` (brain already exists).
#
# PowerShell 5.1 compatible (no &&, no ternary).

param(
  [switch]$Yes,
  [switch]$CopySkills,
  [switch]$SkipInit
)

$ErrorActionPreference = 'Stop'
$repo = 'github:jaypetez/gbrain-copilot'

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }

# Run a native command via cmd so stderr (bun/gbrain progress output) merges
# into stdout as plain text instead of becoming a terminating ErrorRecord
# under $ErrorActionPreference='Stop' (PowerShell 5.1 behavior). Returns the
# native exit code in $LASTEXITCODE.
function Invoke-Native([string]$CommandLine) {
  cmd /c "$CommandLine 2>&1" | ForEach-Object { Write-Host $_ }
}

# --- 1. Bun ---------------------------------------------------------------
Step 'Checking for Bun'
$bun = Get-Command bun -ErrorAction SilentlyContinue
if ($null -eq $bun) {
  Step 'Installing Bun'
  irm https://bun.sh/install.ps1 | iex
  $env:Path = "$env:USERPROFILE\.bun\bin;$env:Path"
  $bun = Get-Command bun -ErrorAction SilentlyContinue
  if ($null -eq $bun) { throw 'Bun installed but not found on PATH. Open a new terminal and re-run this script.' }
  Write-Host 'NOTE: Bun was added to PATH for this session; new terminals pick it up automatically.'
}
Write-Host "Bun $(bun --version)"

# --- 2. gbrain ------------------------------------------------------------
Step "Installing gbrain ($repo)"
Invoke-Native "bun install -g $repo"
if ($LASTEXITCODE -ne 0) { throw "bun install -g $repo failed (transient EPERM on Windows? re-run this script)." }
$gbrain = Get-Command gbrain -ErrorAction SilentlyContinue
if ($null -eq $gbrain) {
  $env:Path = "$env:USERPROFILE\.bun\bin;$env:Path"
  $gbrain = Get-Command gbrain -ErrorAction SilentlyContinue
}
if ($null -eq $gbrain) { throw 'gbrain not found on PATH after install. Run `bun pm bin -g` to find the bin dir and add it to PATH.' }
Invoke-Native 'gbrain --version'

# Bun sometimes skips the postinstall hook on global installs — run the
# migrations explicitly (idempotent; no-op on a fresh install with no brain).
Step 'Applying schema migrations (idempotent)'
Invoke-Native 'gbrain apply-migrations --yes --non-interactive'
if ($LASTEXITCODE -ne 0) { Write-Warning 'apply-migrations reported an issue; `gbrain doctor` will diagnose after init.' }

# --- 3. Brain -------------------------------------------------------------
if (-not $SkipInit) {
  Step 'Creating the brain (PGLite, local, no server)'
  Write-Host 'NOTE: init may ask about embedding providers and search mode — answer the prompts.'
  if ($Yes) { Invoke-Native 'gbrain init --pglite --yes' } else { Invoke-Native 'gbrain init --pglite' }
  if ($LASTEXITCODE -ne 0) { Write-Warning 'gbrain init did not complete cleanly; run `gbrain doctor` for the fix.' }
} else {
  Step 'Skipping gbrain init (-SkipInit)'
}

# --- 4. Copilot CLI MCP config ---------------------------------------------
Step 'Wiring the Copilot CLI MCP config'
if ($env:COPILOT_HOME) { $copilotHome = $env:COPILOT_HOME } else { $copilotHome = Join-Path $env:USERPROFILE '.copilot' }
$configPath = Join-Path $copilotHome 'mcp-config.json'
New-Item -ItemType Directory -Force -Path $copilotHome | Out-Null

$config = $null
if (Test-Path $configPath) {
  try {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
  } catch {
    throw "Existing $configPath is not valid JSON - fix or remove it, then re-run."
  }
}
if ($null -eq $config) { $config = [pscustomobject]@{} }
if ($null -eq ($config.PSObject.Properties['mcpServers'])) {
  $config | Add-Member -MemberType NoteProperty -Name mcpServers -Value ([pscustomobject]@{})
}

$existing = $config.mcpServers.PSObject.Properties['gbrain']
if ($null -ne $existing -and -not $Yes) {
  Write-Warning "An MCP server named 'gbrain' already exists in $configPath. Re-run with -Yes to replace it."
} else {
  $entry = [pscustomobject]@{
    type    = 'local'
    command = 'gbrain'
    args    = @('serve')
    tools   = @('*')
  }
  if ($null -ne $existing) { $config.mcpServers.PSObject.Properties.Remove('gbrain') }
  $config.mcpServers | Add-Member -MemberType NoteProperty -Name gbrain -Value $entry
  $json = $config | ConvertTo-Json -Depth 10
  [IO.File]::WriteAllText($configPath, $json + "`n")
  Write-Host "Wrote gbrain MCP server entry to $configPath"
}

# --- 5. Skills (optional) ---------------------------------------------------
if ($CopySkills) {
  Step 'Copying skills to ~/.copilot/skills/'
  $skillsSrc = Join-Path $PSScriptRoot '..\skills'
  if (-not (Test-Path $skillsSrc)) {
    Write-Warning 'skills/ not found next to this script (one-liner install?). Use /plugin marketplace add jaypetez/gbrain-copilot then /plugin install gbrain@gbrain-copilot inside copilot instead.'
  } else {
    $skillsDest = Join-Path $copilotHome 'skills'
    New-Item -ItemType Directory -Force -Path $skillsDest | Out-Null
    Get-ChildItem $skillsSrc -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') } | ForEach-Object {
      Copy-Item $_.FullName -Destination (Join-Path $skillsDest $_.Name) -Recurse -Force
    }
    Write-Host "Copied skills to $skillsDest (do NOT also install the plugin, or skill names will collide)"
  }
}

# --- 6. Verify + next steps --------------------------------------------------
Step 'Health check'
Invoke-Native 'gbrain doctor'

Write-Host ''
Write-Host '=============================================================' -ForegroundColor Green
Write-Host ' gbrain is wired into GitHub Copilot CLI. Next steps:' -ForegroundColor Green
Write-Host '   1. copilot                      # start Copilot CLI'
Write-Host '   2. /mcp                         # confirm gbrain is running'
if (-not $CopySkills) {
  Write-Host '   3. /plugin marketplace add jaypetez/gbrain-copilot'
  Write-Host '   4. /plugin install gbrain@gbrain-copilot     # skills + gbrain agent'
}
Write-Host '   5. ask: "search my brain for <topic>"'
Write-Host ' Docs: COPILOT.md and docs/mcp/COPILOT_CLI.md' -ForegroundColor Green
Write-Host '=============================================================' -ForegroundColor Green
