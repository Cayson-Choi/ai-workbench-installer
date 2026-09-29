# AI Workbench Installer

Windows bootstrapper for the following tools:

- Claude Code (`@anthropic-ai/claude-code`)
- Obsidian
- LLM Wiki (`nashsu/llm_wiki`)
- Buzz Agent (`block/buzz`)
- Hermes Agent (`NousResearch/hermes-agent`, through WSL2)
- Aside Browser (opens the official beta page; no public installer is available yet)

## One-command install (Windows 10/11)

Open PowerShell and run:

```powershell
irm https://raw.githubusercontent.com/Cayson-Choi/ai-workbench-installer/main/install.ps1 | iex
```

The script is idempotent: run it again to repair or update the tools. It uses WinGet for signed Windows packages, GitHub Releases when available, and builds the two open-source agents from source when a Windows release is not published.

## What you need

- Windows 10 22H2 or Windows 11
- An internet connection
- Administrator permission for WSL2 and some package installs
- API keys/accounts are not created by this installer. Claude Code and Hermes ask for sign-in/provider setup on first run.

## Platform notes

- Hermes Agent officially supports Linux, macOS, WSL2, and Termux. The installer enables WSL2 and installs Hermes in Ubuntu.
- Aside Browser is currently distributed through a private beta/waitlist, so there is no public URL that an installer can safely download. The script opens the official page and reports this clearly.
- Installing these tools does not grant paid subscriptions or API access.

## Manual commands after install

```powershell
wsl -d Ubuntu -- bash -lc 'source ~/.bashrc; hermes setup'
claude
```

The installer writes logs to `%LOCALAPPDATA%\AI-Workbench\install.log`.
