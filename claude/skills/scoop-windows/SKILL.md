---
name: scoop-windows
description: Use on this Windows machine whenever a command-line tool or developer app is missing, must be installed, updated or removed, or when PATH/JAVA_HOME/npm-global questions come up. Explains that software here is managed per-user with Scoop and the Heitorgkk bucket (plus npm and WinGet for a few apps), and how to install things without admin rights.
---

# Installing software on this machine

This machine is provisioned with [Scoop](https://scoop.sh) and the personal
`Heitorgkk` bucket (https://github.com/Heitorgkk/scoop-bucket). Follow these rules
instead of downloading installers, using Chocolatey, or asking for admin rights.

## Rules

1. **Prefer Scoop**, always with an explicit bucket: `scoop install main/jq`, never a bare
   `scoop install jq` when the name could exist in several buckets.
2. **Never elevate.** Scoop installs per user into `~\scoop`. Do not run `scoop` from an
   administrator shell and never pass `--global` unless the user asks.
3. **Find packages first**: `scoop search <name>`, then `scoop info <bucket>/<app>` to read
   its notes (some apps print follow-up steps such as `reg import ...`).
4. **Buckets in use**: `main`, `extras`, `java`, `Heitorgkk`. Add a missing official one with
   `scoop bucket add <name>` (for example `versions`, `nerd-fonts`).
5. **After installing**, a new terminal is needed for PATH changes. In the current session,
   Scoop shims (`~\scoop\shims`) are usually already on PATH; otherwise refresh with:
   `$env:Path = [Environment]::GetEnvironmentVariable('Path','User') + ';' + [Environment]::GetEnvironmentVariable('Path','Machine')`

## Tool groups

Groups are installed with the repository's script (it skips what is already installed):

```powershell
& "$env:USERPROFILE\scoop\buckets\Heitorgkk\scripts\install.ps1" -Group <main|ai|terminal|utilities|claude-extensions|claude-tools|all>
& "$env:USERPROFILE\scoop\buckets\Heitorgkk\scripts\setup-claude.ps1" -Check              # RTK/Graphify/Headroom/plugins report
& "$env:USERPROFILE\scoop\buckets\Heitorgkk\scripts\install.ps1" -Group all -Update   # upgrade everything
& "$env:USERPROFILE\scoop\buckets\Heitorgkk\scripts\status.ps1"                       # what is installed
```

The authoritative list of tools is `~\scoop\buckets\Heitorgkk\groups.json`.

## Non-Scoop tools

- **npm globals** (e.g. `@google/gemini-cli`) live in Scoop's persisted Node prefix
  (`~\scoop\persist\nodejs-lts\bin`) and survive Node updates. Install/upgrade with
  `npm install -g <pkg>@latest`; use `npm.cmd` if `npm.ps1` is blocked by execution policy.
- **Python CLIs** (Graphify `graphifyy`, Headroom `headroom-ai[mcp]`) are `uv tool`s from `main/uv`,
  kept under `~\scoop\persist\uv`. Install/upgrade with `uv tool install --python 3.13 <pkg>` /
  `uv tool upgrade <pkg>`; never `pip install` them globally.
- **Desktop apps** (Claude Desktop `Anthropic.Claude`, ChatGPT `OpenAI.ChatGPT`) come from
  WinGet. If WinGet is unavailable, `install.ps1 -NoWinGet` installs the vendor's signed
  MSIX directly with `Add-AppxPackage`.

## Environment facts

- Java: `temurin-lts-jdk` sets `JAVA_HOME` to `~\scoop\apps\temurin-lts-jdk\current`.
- Rust: `rustup` keeps `CARGO_HOME`/`RUSTUP_HOME` under `~\scoop\persist\rustup`. The MSVC
  toolchain needs Microsoft C++ Build Tools, which are not installed automatically, so the GNU
  toolchain `stable-x86_64-pc-windows-gnu` is used with MSYS2 (`main/msys2`, MINGW64 gcc on PATH via
  `~\scoop\apps\msys2\current\mingw64\bin`). Extra C libraries: `pacman -S mingw-w64-x86_64-<lib>` from a
  `mingw64` shell. After `scoop update msys2`, re-run `install.ps1 -Group main` (it reinstalls gcc).
- Claude Code: the RTK hook, Headroom MCP (no proxy; never set `ANTHROPIC_BASE_URL`), Graphify skill,
  Ponytail and Context Mode plugins come from the `claude-tools` group.
- Docker: `main/docker` is the Docker CLI + engine for **Windows containers only**, not
  Docker Desktop. Use `docker context`/`DOCKER_HOST` for a Linux engine.
- Git for Windows comes from `main/git`; Git Bash is what Claude Code uses on Windows.

## Updating and removing

```powershell
scoop update; scoop update *        # refresh buckets, upgrade all Scoop apps
scoop status                         # what is outdated
scoop uninstall <app>
scoop cleanup *                      # remove old versions
```
