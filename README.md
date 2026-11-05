# Autonomous Dev Environment

A Windows bootstrap for a local-first autonomous software engineering agent based on Hermes Agent.

## Target machine

- Windows 10/11 x64
- AMD Radeon RX 7600 8 GB (Vulkan)
- 32 GB RAM
- Ryzen 5 7500F

## Install

1. Clone or download this repository.
2. Double-click Install-ADE.cmd, or run Install-ADE.ps1 from PowerShell.
3. The installer checks Git, installs Hermes Agent from the official Nous Research installer, ensures Chromium is available, and applies the ADE profile.
4. At the end, open the local-model picker and select the model marked as recommended for this machine.

The installer does not silently download model weights. You choose the model after Hermes has measured the available GPU memory.

## What it configures

- Hermes Agent native Windows installation (no WSL required).
- Chromium browser runtime.
- DuckDuckGo search (DDGS) and Firecrawl extraction (keyless mode where available).
- Persistent memory and user profile.
- Checkpoints and smart command approvals.
- One concurrent subagent and two delegation levels.
- Git worktree isolation for delegated workers.
- Reuse-first software engineering instructions.

## Start working

Open PowerShell in the target project directory and run:

    hermes

For the local-model manager:

    hermes model

For diagnostics:

    hermes doctor
    hermes pm doctor
    hermes config check

## Project instructions

Copy templates/AGENTS.md to the root of each project you want Hermes to work on, or pass -ProjectPath to the installer:

    .\Install-ADE.ps1 -ProjectPath "C:\path\to\your\project"

Existing AGENTS.md and Hermes SOUL.md content is preserved; the installer adds or updates only the ADE-managed section.

## GitHub authentication

Git is required; the installer uses WinGet to install it if it is missing. GitHub CLI is optional and offered interactively. GitHub authentication is not required for public web research or cloning public repositories, but is recommended for authenticated code search, private repositories, and PR workflows. The installer offers to run gh auth login.

## Security and behavior

- The installer uses the official Hermes bootstrap script over HTTPS.
- It never changes the machine-wide PowerShell execution policy.
- It does not disable Hermes approvals.
- It does not enable force-pushes or automatic deletion of user branches.
- Downloaded repositories and dependencies must be reviewed before execution.
- The agent must inspect Git status and preserve pre-existing user changes.
- External source code must be checked for license, compatibility, provenance, and security before integration.

## Logs

Installer logs are written to %TEMP%\Autonomous-Dev-Environment\.

## Official documentation

- https://hermes-agent.nousresearch.com/docs/getting-started/installation
- https://hermes-agent.nousresearch.com/docs/user-guide/local-models
- https://hermes-agent.nousresearch.com/docs/user-guide/features/web-search
