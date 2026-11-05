[CmdletBinding()]
param(
    [string]$ProjectPath,
    [switch]$SkipGitInstall,
    [switch]$SkipGitHubCli,
    [switch]$SkipModelMenu,
    [switch]$NoConfirm
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogRoot = Join-Path $env:TEMP "Autonomous-Dev-Environment"
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
$LogPath = Join-Path $LogRoot ("install-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
$TranscriptStarted = $false

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host ("==> " + $Message) -ForegroundColor Cyan
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @()
    )
    & $FilePath @Arguments
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        throw ("Command failed with exit code {0}: {1} {2}" -f $code, $FilePath, ($Arguments -join " "))
    }
}

function Invoke-Hermes {
    param([string[]]$Arguments)
    & hermes @Arguments
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        throw ("Hermes command failed with exit code {0}: hermes {1}" -f $code, ($Arguments -join " "))
    }
}

function Merge-ManagedSection {
    param(
        [string]$ExistingText,
        [string]$ManagedText,
        [string]$BeginMarker,
        [string]$EndMarker
    )

    $start = $ExistingText.IndexOf($BeginMarker, [System.StringComparison]::Ordinal)
    $finish = $ExistingText.IndexOf($EndMarker, [System.StringComparison]::Ordinal)

    if ($start -ge 0 -and $finish -gt $start) {
        $finish = $finish + $EndMarker.Length
        return $ExistingText.Substring(0, $start) + $ManagedText + $ExistingText.Substring($finish)
    }

    if ([string]::IsNullOrWhiteSpace($ExistingText)) {
        return $ManagedText
    }

    return $ExistingText.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $ManagedText
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Install-WinGetPackage {
    param([string]$PackageId)
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "WinGet is unavailable. Install the package manually, then rerun this installer."
    }

    Invoke-Native -FilePath $winget.Source -Arguments @(
        "install", "--id", $PackageId, "--exact", "--source", "winget",
        "--silent", "--accept-package-agreements", "--accept-source-agreements"
    )
}

function Refresh-UserPath {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $env:Path = (($userPath, $machinePath) -join ";")
}

try {
    try {
        Start-Transcript -Path $LogPath -Force | Out-Null
        $TranscriptStarted = $true
    }
    catch {
        Write-Warning ("Could not start transcript logging: " + $_.Exception.Message)
    }

    Write-Host "Autonomous Dev Environment - Windows bootstrap" -ForegroundColor Green
    Write-Host ("Log: " + $LogPath)
    Write-Host "This installs Hermes Agent and its browser runtime, then configures the local-first coding profile."
    Write-Host "It does not change machine-wide execution policy or download a model without your selection."

    if ($env:OS -ne "Windows_NT") {
        throw "This installer is for native Windows."
    }
    if (-not [Environment]::Is64BitOperatingSystem) {
        throw "A 64-bit Windows installation is required."
    }
    if ($PSVersionTable.PSVersion.Major -lt 5 -or ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
        throw "PowerShell 5.1 or newer is required."
    }

    if (-not $NoConfirm) {
        $answer = Read-Host "Continue with installation? [Y/N]"
        if ($answer -notmatch "^(?i:y|yes|д|да)$") {
            Write-Host "Installation cancelled."
            return
        }
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    Write-Step "Checking Git"
    $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $gitCommand) {
        if ($SkipGitInstall) {
            throw "Git is required but was not found. Install Git for Windows, then rerun."
        }

        Write-Host "Git for Windows is missing. Installing it with WinGet..."
        Install-WinGetPackage -PackageId "Git.Git"

        $gitCandidates = @(
            (Join-Path $env:ProgramFiles "Git\cmd\git.exe"),
            (Join-Path $env:LOCALAPPDATA "Programs\Git\cmd\git.exe"),
            (Join-Path $env:ProgramFiles "Git\bin\git.exe")
        )
        $gitExe = $gitCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $gitExe) {
            Refresh-UserPath
            $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
            if ($gitCommand) {
                $gitExe = $gitCommand.Source
            }
        }
        if (-not $gitExe) {
            throw "Git installation completed but git.exe was not found. Restart Windows Terminal and rerun."
        }
        $gitDirectory = Split-Path -Parent $gitExe
        $env:Path = $gitDirectory + ";" + $env:Path
    }
    Invoke-Native -FilePath (Get-Command git.exe).Source -Arguments @("--version")

    Write-Step "Installing Hermes Agent from the official installer"
    $bootstrapUri = "https://hermes-agent.nousresearch.com/install.ps1"
    $bootstrapResponse = Invoke-WebRequest -Uri $bootstrapUri -UseBasicParsing -Headers @{
        "User-Agent" = "Autonomous-Dev-Environment-Installer"
    }
    $bootstrapText = [string]$bootstrapResponse.Content
    if ([string]::IsNullOrWhiteSpace($bootstrapText) -or $bootstrapText -notmatch "Hermes") {
        throw "The official Hermes bootstrap response was empty or unexpected. No installer code was executed."
    }

    $bootstrap = [scriptblock]::Create($bootstrapText)
    & $bootstrap -NonInteractive -Channel stable

    $hermesBin = Join-Path $env:LOCALAPPDATA "hermes\bin"
    if (Test-Path $hermesBin) {
        $env:Path = $hermesBin + ";" + $env:Path
    }
    Refresh-UserPath
    if (Test-Path $hermesBin) {
        $env:Path = $hermesBin + ";" + $env:Path
    }

    $hermesCommand = Get-Command hermes -ErrorAction SilentlyContinue
    if (-not $hermesCommand) {
        throw "Hermes installation finished, but the hermes command is not on PATH. Open a new PowerShell window and rerun this installer."
    }

    Write-Step "Verifying Hermes"
    Invoke-Hermes -Arguments @("--version")

    Write-Step "Ensuring the local Chromium browser"
    Invoke-Hermes -Arguments @("pm", "install", "chromium")

    Write-Step "Configuring web research, memory, delegation, and safety"
    $settings = @(
        @("web.search_backend", "ddgs"),
        @("web.extract_backend", "firecrawl"),
        @("memory.memory_enabled", "true"),
        @("memory.user_profile_enabled", "true"),
        @("delegation.max_concurrent_children", "1"),
        @("delegation.max_spawn_depth", "2"),
        @("delegation.orchestrator_enabled", "true"),
        @("delegation.worktree_isolation", "true"),
        @("approvals.mode", "smart"),
        @("checkpoints.enabled", "true"),
        @("checkpoints.max_snapshots", "20"),
        @("security.redact_secrets", "true"),
        @("security.allow_lazy_installs", "true"),
        @("skills.guard_agent_created", "true")
    )

    foreach ($setting in $settings) {
        Write-Host ("  " + $setting[0] + " = " + $setting[1])
        Invoke-Hermes -Arguments @("config", "set", $setting[0], $setting[1])
    }

    Write-Step "Installing the ADE agent instructions"
    $soulSource = Join-Path $RepoRoot "agent\SOUL.md"
    if (-not (Test-Path $soulSource)) {
        throw "Missing profile file: $soulSource"
    }

    $hermesHome = Join-Path $env:LOCALAPPDATA "hermes"
    New-Item -ItemType Directory -Path $hermesHome -Force | Out-Null
    $soulTarget = Join-Path $hermesHome "SOUL.md"
    $managedSoul = [System.IO.File]::ReadAllText($soulSource)
    if (Test-Path $soulTarget) {
        $existingSoul = [System.IO.File]::ReadAllText($soulTarget)
    }
    else {
        $existingSoul = ""
    }

    $mergedSoul = Merge-ManagedSection -ExistingText $existingSoul -ManagedText $managedSoul -BeginMarker "<!-- ADE:BEGIN -->" -EndMarker "<!-- ADE:END -->"
    Write-Utf8NoBom -Path $soulTarget -Content $mergedSoul
    Write-Host ("Installed profile: " + $soulTarget)

    if ($ProjectPath) {
        Write-Step "Installing project-specific instructions"
        $project = Resolve-Path -LiteralPath $ProjectPath -ErrorAction Stop
        $projectRoot = $project.Path
        if (-not (Test-Path -LiteralPath $projectRoot -PathType Container)) {
            throw "ProjectPath must point to an existing directory."
        }
        $templatePath = Join-Path $RepoRoot "templates\AGENTS.md"
        if (-not (Test-Path $templatePath)) {
            throw "Missing project template: $templatePath"
        }

        $agentsTarget = Join-Path $projectRoot "AGENTS.md"
        $managedAgents = [System.IO.File]::ReadAllText($templatePath)
        if (Test-Path $agentsTarget) {
            $existingAgents = [System.IO.File]::ReadAllText($agentsTarget)
        }
        else {
            $existingAgents = ""
        }
        $mergedAgents = Merge-ManagedSection -ExistingText $existingAgents -ManagedText $managedAgents -BeginMarker "<!-- ADE:BEGIN -->" -EndMarker "<!-- ADE:END -->"
        Write-Utf8NoBom -Path $agentsTarget -Content $mergedAgents
        Write-Host ("Installed project rules: " + $agentsTarget)
    }

    Write-Step "Running diagnostics"
    try {
        Invoke-Hermes -Arguments @("doctor")
    }
    catch {
        Write-Warning ("Hermes doctor reported a problem: " + $_.Exception.Message)
    }
    try {
        Invoke-Hermes -Arguments @("pm", "doctor")
    }
    catch {
        Write-Warning ("Package manager diagnostics reported a problem: " + $_.Exception.Message)
    }
    try {
        Invoke-Hermes -Arguments @("config", "check")
    }
    catch {
        Write-Warning ("Configuration validation reported a problem: " + $_.Exception.Message)
    }

    Write-Step "Optional GitHub CLI"
    $ghCommand = Get-Command gh.exe -ErrorAction SilentlyContinue
    if (-not $ghCommand -and -not $SkipGitHubCli) {
        $installGh = Read-Host "Install GitHub CLI for authenticated GitHub search and repository workflows? [Y/N]"
        if ($installGh -match "^(?i:y|yes|д|да)$") {
            try {
                Install-WinGetPackage -PackageId "GitHub.cli"
                Refresh-UserPath
                $ghCommand = Get-Command gh.exe -ErrorAction SilentlyContinue
            }
            catch {
                Write-Warning ("GitHub CLI was not installed: " + $_.Exception.Message)
            }
        }
    }

    if ($ghCommand) {
        & gh auth status 2>$null
        if ($LASTEXITCODE -ne 0) {
            $login = Read-Host "GitHub CLI is not authenticated. Run gh auth login now? [Y/N]"
            if ($login -match "^(?i:y|yes|д|да)$") {
                & gh auth login
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "GitHub authentication was not completed. Public web research and Git cloning still work."
                }
            }
        }
    }

    Write-Host ""
    Write-Host "Installation and base configuration completed." -ForegroundColor Green
    Write-Host ("Log: " + $LogPath)
    Write-Host "Next commands:"
    Write-Host "  hermes model     - select and download a local model sized for this GPU"
    Write-Host "  hermes           - start the agent in the current project directory"
    Write-Host "  hermes desktop   - launch the desktop interface, if desired"

    if (-not $SkipModelMenu) {
        $openModelMenu = Read-Host "Open the local model manager now? The model will download only after you select it. [Y/N]"
        if ($openModelMenu -match "^(?i:y|yes|д|да)$") {
            Invoke-Hermes -Arguments @("model")
        }
    }
}
catch {
    Write-Host ""
    Write-Host ("INSTALLATION FAILED: " + $_.Exception.Message) -ForegroundColor Red
    Write-Host ("Review the log: " + $LogPath) -ForegroundColor Yellow
    Write-Host "Existing project source files were not intentionally modified. The Hermes profile or optional project AGENTS.md may already have been updated."
    exit 1
}
finally {
    if ($TranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
        }
        catch {}
    }
}
