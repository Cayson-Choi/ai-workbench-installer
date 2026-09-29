#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$SkipWsl,
    [switch]$SkipBuilds,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Root = Join-Path $env:LOCALAPPDATA 'AI-Workbench'
$Log = Join-Path $Root 'install.log'
New-Item -ItemType Directory -Force -Path $Root | Out-Null

function Write-Step([string]$Message) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Write-Host $line -ForegroundColor Cyan
    Add-Content -Path $Log -Value $line
}
function Write-Warn([string]$Message) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] WARNING: $Message"
    Write-Warning $Message
    Add-Content -Path $Log -Value $line
}
function Test-Command([string]$Name) { return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue) }
function Invoke-Winget([string]$Id, [string]$Name) {
    if (-not (Test-Command 'winget')) { throw 'WinGet is required. Install App Installer from Microsoft Store, then rerun.' }
    if (winget list --id $Id --exact --accept-source-agreements 2>$null | Select-String -SimpleMatch $Id) {
        Write-Step "$Name is already installed"
        return
    }
    Write-Step "Installing $Name ($Id)"
    winget install --id $Id --exact --source winget --accept-package-agreements --accept-source-agreements --silent
}
function Get-LatestReleaseAsset([string]$Repo, [string[]]$Patterns) {
    $headers = @{ 'User-Agent' = 'ai-workbench-installer' }
    $release = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$Repo/releases/latest"
    foreach ($pattern in $Patterns) {
        $asset = $release.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
        if ($asset) { return $asset }
    }
    return $null
}
function Install-GitHubRelease([string]$Repo, [string[]]$Patterns, [string]$Name) {
    $asset = Get-LatestReleaseAsset $Repo $Patterns
    if (-not $asset) { return $false }
    $download = Join-Path $Root $asset.name
    Write-Step "Downloading $Name release $($asset.name)"
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $download
    $ext = [IO.Path]::GetExtension($download).ToLowerInvariant()
    if ($ext -eq '.msi') { Start-Process msiexec.exe -ArgumentList "/i `"$download`" /qn /norestart" -Wait }
    elseif ($ext -eq '.exe') { Start-Process $download -ArgumentList '/S' -Wait }
    elseif ($ext -eq '.zip') {
        $dir = Join-Path $Root ($Name -replace '\s','-')
        Expand-Archive $download -DestinationPath $dir -Force
        $exe = Get-ChildItem $dir -Recurse -Filter *.exe | Select-Object -First 1
        if ($exe) { Copy-Item $exe.FullName (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps') -Force }
    }
    return $true
}
function Ensure-Path([string]$Path) {
    if ($env:Path -notlike "*$Path*") { $env:Path = "$Path;$env:Path" }
}

Start-Transcript -Path $Log -Append | Out-Null
try {
    Write-Step 'Starting AI Workbench installation'
    Invoke-Winget 'Git.Git' 'Git'
    Invoke-Winget 'OpenJS.NodeJS.LTS' 'Node.js LTS'
    Invoke-Winget 'Obsidian.Obsidian' 'Obsidian'
    if (-not (Test-Command 'npm')) { Ensure-Path (Join-Path $env:ProgramFiles 'nodejs') }
    if (-not (Test-Command 'npm')) { throw 'npm was not found after installing Node.js. Open a new PowerShell and rerun.' }

    Write-Step 'Installing/updating Claude Code'
    npm install --global @anthropic-ai/claude-code

    if (-not $SkipBuilds) {
        Invoke-Winget 'Rustlang.Rustup' 'Rust toolchain'
        if (-not (Test-Command 'cargo')) { Ensure-Path (Join-Path $env:USERPROFILE '.cargo\bin') }
        $src = Join-Path $Root 'src'
        New-Item -ItemType Directory -Force -Path $src | Out-Null

        Write-Step 'Installing LLM Wiki'
        $llmInstalled = Install-GitHubRelease 'nashsu/llm_wiki' @('(?i)windows.*(msi|exe|zip)$','(?i)(msi|exe|zip)$') 'LLM Wiki'
        if (-not $llmInstalled) {
            $llmDir = Join-Path $src 'llm_wiki'
            if (-not (Test-Path $llmDir)) { git clone --depth 1 https://github.com/nashsu/llm_wiki.git $llmDir }
            Write-Warn 'LLM Wiki has no Windows release asset yet; source was downloaded to %LOCALAPPDATA%\AI-Workbench\src\llm_wiki. See its README for build instructions.'
        }

        Write-Step 'Installing Buzz Agent'
        $buzzInstalled = Install-GitHubRelease 'block/buzz' @('(?i)windows.*(msi|exe|zip)$','(?i)(windows|win).*(zip|exe)$') 'Buzz Agent'
        if (-not $buzzInstalled) {
            $buzzDir = Join-Path $src 'buzz'
            if (-not (Test-Path $buzzDir)) { git clone --depth 1 https://github.com/block/buzz.git $buzzDir }
            Push-Location $buzzDir
            try {
                cargo build --release -p buzz-agent
                $bin = Get-ChildItem (Join-Path $buzzDir 'target\release') -Filter 'buzz-agent.exe' -Recurse | Select-Object -First 1
                if ($bin) { Copy-Item $bin.FullName (Join-Path $Root 'buzz-agent.exe') -Force }
            } catch { Write-Warn "Buzz Agent source build failed: $($_.Exception.Message). Source remains at $buzzDir." }
            finally { Pop-Location }
        }
    }

    if (-not $SkipWsl) {
        Write-Step 'Enabling WSL2 and installing Hermes Agent'
        try {
            wsl --install --no-launch
            wsl --set-default-version 2
            $distros = wsl --list --quiet 2>$null | Out-String
            if ($distros -notmatch '(?m)^Ubuntu\s*$') { wsl --install -d Ubuntu --no-launch }
            Write-Step 'Installing Hermes inside Ubuntu (first launch may require a reboot)'
            wsl -d Ubuntu -- bash -lc "curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash"
        } catch { Write-Warn "WSL/Hermes setup needs a reboot or manual completion: $($_.Exception.Message)" }
    }

    Write-Step 'Aside Browser is private beta; opening the official page'
    if (-not $NoLaunch) { Start-Process 'https://aside.faizintifada.com/' }
    Write-Host ''
    Write-Host 'Installation finished. Reboot if Windows asks, then run: wsl -d Ubuntu -- hermes setup' -ForegroundColor Green
} finally {
    Stop-Transcript | Out-Null
}
