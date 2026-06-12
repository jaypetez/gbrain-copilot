# install-copilot.ps1 — set up gbrain for GitHub Copilot CLI on Windows.
#
# Installs Bun if missing, installs gbrain from this fork, runs schema
# migrations, creates a local PGLite brain, and merges the gbrain MCP server
# entry into Copilot CLI's mcp-config.json (preserving existing servers).
#
# Usage (from a clone):    .\scripts\install-copilot.ps1 [-Yes] [-CopySkills] [-SkipInit]
# Usage (one-liner):       irm https://raw.githubusercontent.com/jaypetez/gbrain-copilot/main/scripts/install-copilot.ps1 | iex
#
#   -Yes         Non-interactive: unattended `gbrain init` (embedding provider
#                auto-resolved from env keys; no keys = --no-embedding) and
#                replace an existing gbrain MCP entry if present.
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

# Bun blocks the postinstall hook on global installs (the "Blocked 1
# postinstall" message above) — run the migrations explicitly (idempotent;
# no-op on a fresh install with no brain).
Step 'Applying schema migrations (works around Bun blocking the postinstall hook)'
$migOut = cmd /c 'gbrain apply-migrations --yes --non-interactive 2>&1'
$migExit = $LASTEXITCODE
if (($migOut | Out-String).Trim() -eq '') {
  Write-Host '(no output: fresh install - no brain yet, so nothing to migrate; init comes next)'
} else {
  $migOut | ForEach-Object { Write-Host $_ }
}
if ($migExit -ne 0) { Write-Warning 'apply-migrations reported an issue; `gbrain doctor` will diagnose after init.' }

# --- 3. Brain -------------------------------------------------------------
if (-not $SkipInit) {
  Step 'Creating the brain (PGLite, local, no server)'
  if ($Yes) {
    # gbrain init has no --yes flag; --pglite --non-interactive is the
    # unattended path. Detect embedding provider keys to pick the right flags.
    $keyNames = @('OPENAI_API_KEY', 'ZEROENTROPY_API_KEY', 'VOYAGE_API_KEY', 'GOOGLE_GENERATIVE_AI_API_KEY', 'DASHSCOPE_API_KEY', 'MINIMAX_API_KEY', 'OPENROUTER_API_KEY', 'ZHIPUAI_API_KEY')
    $detected = @($keyNames | Where-Object { -not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($_)) })
    if (-not [string]::IsNullOrEmpty($env:AZURE_OPENAI_API_KEY) -and -not [string]::IsNullOrEmpty($env:AZURE_OPENAI_ENDPOINT) -and -not [string]::IsNullOrEmpty($env:AZURE_OPENAI_DEPLOYMENT)) {
      $detected += 'AZURE_OPENAI_*'
    }
    if ($detected.Count -eq 0) {
      Write-Warning 'No embedding provider API key detected (OPENAI_API_KEY, VOYAGE_API_KEY, ...).'
      Write-Warning 'Creating the brain WITHOUT embeddings — keyword search works; semantic search is disabled.'
      Write-Warning 'To enable later: set a provider key, then run: gbrain config set embedding_model openai:text-embedding-3-large'
      $initCmd = 'gbrain init --pglite --non-interactive --no-embedding'
    } else {
      if ($detected.Count -gt 1) {
        # No em-dash here: this string is double-quoted, and PS 5.1 misdecodes
        # BOM-less UTF-8 em-dashes into a smart quote that terminates it early.
        Write-Warning "Multiple embedding provider keys detected ($($detected -join ', ')); init refuses the ambiguity non-interactively (exits with its own disambiguation message); the health check below turns that into a PARTIAL INSTALL."
      }
      $initCmd = 'gbrain init --pglite --non-interactive'
    }
    # The search-mode picker checks stdin's TTY directly and ignores
    # --non-interactive, so stdin must come from NUL or init stalls on a
    # hidden menu. cmd parses the `< NUL` alongside the 2>&1 Invoke-Native
    # appends (redirections compose anywhere on a cmd line).
    Invoke-Native "$initCmd < NUL"
  } else {
    Write-Host 'NOTE: init may ask about embedding providers and search mode — answer the prompts.'
    Invoke-Native 'gbrain init --pglite'
  }
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
$doctorOut = cmd /c 'gbrain doctor 2>&1'
$doctorExit = $LASTEXITCODE
if ($null -ne $doctorOut) { $doctorOut | ForEach-Object { Write-Host $_ } }
# doctor exits 0=ok, 1=warnings, 2+=failure. Warnings are expected on a fresh
# --no-embedding brain; only a hard failure (or no brain at all) is partial.
if ($doctorExit -ge 2 -or ($doctorOut | Out-String) -match 'No brain configured') {
  Write-Host ''
  Write-Host '=============================================================' -ForegroundColor Red
  Write-Host ' PARTIAL INSTALL: the gbrain MCP entry was written, but the' -ForegroundColor Red
  Write-Host ' brain is not healthy — Copilot CLI will list gbrain, but' -ForegroundColor Red
  Write-Host ' queries will fail.' -ForegroundColor Red
  Write-Host '   Fix:      gbrain init --pglite   (then re-run this script)' -ForegroundColor Red
  Write-Host '   Diagnose: gbrain doctor --json' -ForegroundColor Red
  Write-Host '=============================================================' -ForegroundColor Red
  exit 1
}
if ($doctorExit -eq 1) {
  Write-Host 'NOTE: gbrain doctor reported warnings (exit 1) — expected for a fresh brain without embeddings.'
}

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
