# Heitorgkk Scoop Bucket

A personal [Scoop](https://scoop.sh) bucket that works as a **catalog of well-known Windows tools**,
installable one by one or in **groups**. Groups are metapackages: they
don't copy official manifests. They depend on the packages in
[ScoopInstaller/Main](https://github.com/ScoopInstaller/Main),
[Extras](https://github.com/ScoopInstaller/Extras) and
[Java](https://github.com/ScoopInstaller/Java). Tools that have no reliable Scoop
package (Claude Desktop, ChatGPT Desktop, Gemini CLI) are installed from their
official channels by [`scripts/install.ps1`](scripts/install.ps1): npm, and WinGet or,
where WinGet is missing or blocked, the vendor's signed MSIX. The same script sets up
**Claude Code plugins and skills**.

**Fastest start on a fresh machine** (no Scoop, Git or WinGet needed; normal PowerShell window, not admin):

```powershell
irm https://raw.githubusercontent.com/Heitorgkk/scoop-bucket/main/setup.ps1 | iex
```

| Group | Title | Scoop | Script |
|---|---|---|---|
| `main` | Essential Development Tools | `scoop install Heitorgkk/main` | `.\scripts\install.ps1 -Group main` |
| `ai` | AI & Coding Agents | `scoop install Heitorgkk/ai` (Scoop tools only) | `.\scripts\install.ps1 -Group ai` |
| `terminal` | Terminal & CLI | `scoop install Heitorgkk/terminal` | `.\scripts\install.ps1 -Group terminal` |
| `utilities` | Windows Utilities | `scoop install Heitorgkk/utilities` | `.\scripts\install.ps1 -Group utilities` |
| `claude-extensions` | Claude Code Plugins & Skills | `scoop install Heitorgkk/claude-extensions` (only Claude Code + Git) | `.\scripts\install.ps1 -Group claude-extensions` |
| `all` | Complete Environment | `scoop install Heitorgkk/all` (Scoop tools only) | `.\scripts\install.ps1 -Group all` |

## Requirements

- Windows 10 2004 (build 19041) or later, x64 or ARM64.
- Windows PowerShell 5.1 or PowerShell 7+.
- [Scoop](https://scoop.sh). `bootstrap.ps1 -InstallScoop` can install it for you.
- Git. Scoop needs it to add buckets; `bootstrap.ps1` installs `main/git` when it's missing.
- For the desktop apps: [WinGet / App Installer](https://aka.ms/getwinget), which ships with current Windows 10/11,
  **or** MSIX sideloading (on by default since Windows 10 2004) for the WinGet-free route.
- For the npm tools: Node.js 20+. `install.ps1` installs `main/nodejs-lts` when `npm` is missing.
- For plugins: Claude Code (`main/claude-code`, installed automatically) and Git.
- No administrator rights are needed. Run everything from a **normal** (non-elevated) shell.

## Quick start

### Option A: Scoop only

```powershell
scoop bucket add extras
scoop bucket add java
scoop bucket add Heitorgkk https://github.com/Heitorgkk/scoop-bucket
scoop install Heitorgkk/main
```

> The bucket **must** be added with the name `Heitorgkk`. `Heitorgkk/all` depends on
> `Heitorgkk/main`, `Heitorgkk/ai`, and so on. The `extras` and `java` buckets must exist
> too, or Scoop stops with `Bucket 'extras' not added`.

Install any group:

```powershell
scoop install Heitorgkk/main
scoop install Heitorgkk/ai
scoop install Heitorgkk/terminal
scoop install Heitorgkk/utilities
scoop install Heitorgkk/all
```

A metapackage installs only the **Scoop** part of a group. After installing it, its
notes list the npm/WinGet tools that are still missing.

### Option B: complete install with the scripts (Scoop + npm + desktop apps + Claude plugins)

Once the bucket is added (option A), the scripts are already on disk:

```powershell
& "$env:USERPROFILE\scoop\buckets\Heitorgkk\scripts\install.ps1" -Group all
```

On a machine that has nothing yet, `setup.ps1` does everything in one line. It downloads
this repository as a ZIP (no Git), installs Scoop if needed and runs `install.ps1`:

```powershell
irm https://raw.githubusercontent.com/Heitorgkk/scoop-bucket/main/setup.ps1 | iex
```

With options, for example only some groups and no WinGet:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Heitorgkk/scoop-bucket/main/setup.ps1))) -Group main,ai -NoWinGet
```

`setup.ps1` accepts `-Group` (default `all`), `-NoWinGet` and `-Update`. It never closes your
shell, and re-running it is safe because installed tools are skipped.

Or from a clone of this repository:

```powershell
git clone https://github.com/Heitorgkk/scoop-bucket
cd scoop-bucket
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
.\scripts\bootstrap.ps1 -InstallScoop
.\scripts\install.ps1 -Group all
```

## Scripts

### `scripts/bootstrap.ps1`

Prepares the environment. You can run it as often as you like:

1. Checks for Scoop. If it's missing, the script prints the official install commands,
   or installs Scoop when you pass `-InstallScoop`. It refuses to install from an elevated shell.
2. Installs `main/git` if Git is missing.
3. Adds the official buckets declared in `groups.json` (`main`, `extras`, `java`) and the
   `Heitorgkk` bucket. Buckets that already exist are skipped. If one of these repositories
   was added under a *different* name, the script reports it and tells you how to fix it.

```powershell
.\scripts\bootstrap.ps1                      # all buckets
.\scripts\bootstrap.ps1 -Bucket extras       # only extras (+ Heitorgkk)
.\scripts\bootstrap.ps1 -InstallScoop        # also install Scoop if missing
.\scripts\bootstrap.ps1 -BucketSource C:\src\scoop-bucket   # test a local checkout
```

### `scripts/install.ps1`

```powershell
.\scripts\install.ps1 -Group main
.\scripts\install.ps1 -Group ai
.\scripts\install.ps1 -Group terminal
.\scripts\install.ps1 -Group utilities
.\scripts\install.ps1 -Group all
.\scripts\install.ps1 -Group ai,terminal     # several groups; tools are de-duplicated
.\scripts\install.ps1 -Group all -DryRun     # show the plan, change nothing
.\scripts\install.ps1 -Group all -Update     # upgrade what is already installed
.\scripts\install.ps1 -Group ai -ScoopOnly   # skip npm, desktop apps and Claude plugins/skills
.\scripts\install.ps1 -Group ai -NoWinGet    # desktop apps from the official MSIX, never WinGet
.\scripts\install.ps1 -Group claude-extensions   # Claude Code plugins + skills
```

What it does:

1. Checks the group names against `groups.json`. An invalid name exits with code 2 before anything changes.
2. Runs `bootstrap.ps1` for the buckets that the selected groups need.
3. Installs in this order: Scoop tools, npm tools, Claude skills, Claude plugins, desktop apps.
   A tool that is already installed is **skipped**, or upgraded if you pass `-Update`.
   Each step shows `[n/total]` progress.
4. Registers the `Heitorgkk/<group>` metapackage. Later, `scoop update <group>` picks up
   tools that were added to the group.
5. Prints a summary table.

| Exit code | Meaning |
|---|---|
| `0` | Everything is installed or already present |
| `1` | At least one tool failed (see the summary) |
| `2` | Invalid arguments or missing prerequisite; nothing was installed |

### `scripts/status.ps1`

Read-only report of what is installed. It exits with 1 if something is missing.

```powershell
.\scripts\status.ps1                          # every group
.\scripts\status.ps1 -Group ai -MissingOnly   # only what is missing from 'ai'
```

### Desktop apps without WinGet

Claude Desktop and ChatGPT are normally installed with WinGet. When WinGet is missing, blocked
by policy (it exists but doesn't run), or fails, or when you pass `-NoWinGet`, `install.ps1`
uses the vendor's own signed MSIX instead, with no admin rights:

1. It downloads the latest package for your architecture (x64/ARM64) from the vendor:
   - Claude: `claude.ai/api/desktop/win32/<arch>/msix/latest/redirect`, which redirects to `downloads.claude.ai`.
   - ChatGPT: `persistent.oaistatic.com/codex-app-prod/ChatGPT-<arch>.msix`.
2. It checks the package name and publisher inside `AppxManifest.xml`, and the Authenticode signer.
3. It skips the install if the same or a newer version is already present.
4. It runs `Add-AppxPackage` for the current user. Windows verifies the signature again.

An app is detected however it was installed (MSIX, the vendor's classic installer, or WinGet),
so switching routes never installs it twice. This route needs MSIX sideloading, which is on by
default; if IT has disabled both WinGet and sideloading, these two apps can't be installed
without IT. Everything else in the catalog doesn't depend on either.

### Claude Code plugins and skills

The `claude-extensions` group (also part of `all`) configures Claude Code for the current user:

- **Marketplaces** (from `claudeMarketplaces` in `groups.json`): `claude-plugins-official`
  ([anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official)) and
  `anthropic-agent-skills` ([anthropics/skills](https://github.com/anthropics/skills)). Each one is
  added only if it's missing (`claude plugin marketplace add`).
- **Plugins**: installed with `claude plugin install <plugin>@<marketplace> --scope user`.
  With `-Update`, the marketplace is refreshed first and then `claude plugin update` runs.
- **Skills**: personal skills that live in this repository under `claude/skills/<name>/`. They are
  copied to `~/.claude/skills/<name>`, or `$env:CLAUDE_CONFIG_DIR\skills`. A copy you edited locally
  isn't overwritten unless you pass `-Update`.
  - `scoop-windows` teaches Claude Code how this machine is managed: Scoop with explicit buckets,
    never elevated, the Heitorgkk groups, npm globals, and the WinGet/MSIX apps.

Restart Claude Code after installing so it loads them. To add a plugin, add an entry with
`"source": "claude-plugin"` and `"package": "<plugin>@<marketplace>"`; to add a skill, create
`claude/skills/<name>/SKILL.md` and an entry with `"source": "claude-skill"`. See
[Adding a tool](#adding-a-tool).

## Tools

The table below is generated from [`groups.json`](groups.json).

<!-- BEGIN GENERATED TOOLS TABLE (tools/catalog.py generate) -->
| Group | Tool | Description | Source | Notes |
|---|---|---|---|---|
| `main` | [gh](https://cli.github.com/) | GitHub CLI | Scoop `main/gh` |  |
| `main` | [git](https://gitforwindows.org/) | Git for Windows (portable) | Scoop `main/git` |  |
| `main` | [nodejs](https://nodejs.org/) | Node.js, current LTS line (includes npm) | Scoop `main/nodejs-lts` |  |
| `main` | [jdk](https://adoptium.net/) | Eclipse Temurin JDK, latest LTS (sets JAVA_HOME) | Scoop `java/temurin-lts-jdk` | x64 build only; runs under emulation on Windows 11 ARM64. |
| `main` | [rustup](https://rustup.rs/) | Rust toolchain manager (MSVC host by default) | Scoop `main/rustup` | The MSVC toolchain needs Microsoft C++ Build Tools (MSVC + Windows SDK), installed separately. |
| `main` | [docker](https://www.docker.com/) | Docker CLI + Docker Engine (dockerd) for Windows containers. NOT Docker Desktop | Scoop `main/docker` | dockerd only runs Windows containers and needs the Windows 'Containers' feature; registering the service (dockerd --register-service) needs an elevated shell. The CLI can talk to any remote/WSL Linux engine. x64 only. |
| `ai` | [claude-code](https://code.claude.com/) | Claude Code CLI (official Anthropic native binary) | Scoop `main/claude-code` | Needs Git for Windows (Git Bash); provided by the main group. |
| `ai` | [claude-gui](https://claude.com/download) | Claude Desktop, official Anthropic installer | WinGet `Anthropic.Claude` or official MSIX | WinGet, or (with -NoWinGet / when WinGet is unavailable) MSIX sideloading. Windows 10 2004 (19041) or later. |
| `ai` | [gemini-cli](https://github.com/google-gemini/gemini-cli) | Google Gemini CLI (official npm package) | npm `@google/gemini-cli` | Node.js 20+ / npm. install.ps1 installs main/nodejs-lts first when npm is missing. |
| `ai` | [codex](https://github.com/openai/codex) | OpenAI Codex CLI | Scoop `main/codex` |  |
| `ai` | [chatgpt-gui](https://chatgpt.com/download) | ChatGPT Desktop, official OpenAI MSIX | WinGet `OpenAI.ChatGPT` or official MSIX | WinGet, or (with -NoWinGet / when WinGet is unavailable) MSIX sideloading. Windows 10 2004 (19041) or later. |
| `ai` | [opencode](https://opencode.ai/) | OpenCode CLI (v2; not the desktop app) | Scoop `main/opencode` | v2 config is incompatible with v1; see https://opencode.ai/docs/migrate-v1/. |
| `terminal` | [windows-terminal](https://github.com/microsoft/terminal) | Windows Terminal (portable) | Scoop `extras/windows-terminal` |  |
| `terminal` | [oh-my-posh](https://ohmyposh.dev/) | Prompt theme engine | Scoop `main/oh-my-posh` | Enable it in your shell profile; see https://ohmyposh.dev/docs/installation/prompt. A Nerd Font is recommended. |
| `terminal` | [ripgrep](https://github.com/BurntSushi/ripgrep) | Fast recursive text search | Scoop `main/ripgrep` |  |
| `terminal` | [fastfetch](https://github.com/fastfetch-cli/fastfetch) | System information tool | Scoop `main/fastfetch` |  |
| `terminal` | [fzf](https://github.com/junegunn/fzf) | Command-line fuzzy finder | Scoop `main/fzf` |  |
| `terminal` | [bat](https://github.com/sharkdp/bat) | cat clone with syntax highlighting | Scoop `main/bat` |  |
| `terminal` | [lazygit](https://github.com/jesseduffield/lazygit) | Terminal UI for git | Scoop `extras/lazygit` |  |
| `utilities` | [everything](https://www.voidtools.com/) | Instant file search by name | Scoop `extras/everything` |  |
| `utilities` | [powertoys](https://github.com/microsoft/PowerToys) | Microsoft PowerToys | Scoop `extras/powertoys` |  |
| `utilities` | [sharex](https://getsharex.com/) | Screenshot and screen capture | Scoop `extras/sharex` | x64 build only; runs under emulation on Windows 11 ARM64. |
| `utilities` | [7zip](https://www.7-zip.org/) | File archiver | Scoop `main/7zip` |  |
| `utilities` | [localsend](https://localsend.org/) | Local network file sharing | Scoop `extras/localsend` |  |
| `claude-extensions` | [commit-commands](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/commit-commands) | Slash commands for commit, push and PR workflows | Claude plugin `commit-commands@claude-plugins-official` |  |
| `claude-extensions` | [feature-dev](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/feature-dev) | Guided feature development with explorer/architect/reviewer agents | Claude plugin `feature-dev@claude-plugins-official` |  |
| `claude-extensions` | [code-review](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/code-review) | Multi-agent pull request review | Claude plugin `code-review@claude-plugins-official` |  |
| `claude-extensions` | [pr-review-toolkit](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/pr-review-toolkit) | Specialised PR review agents (tests, errors, types, comments) | Claude plugin `pr-review-toolkit@claude-plugins-official` |  |
| `claude-extensions` | [security-guidance](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/security-guidance) | Security warnings and review for edited code | Claude plugin `security-guidance@claude-plugins-official` |  |
| `claude-extensions` | [claude-md-management](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/claude-md-management) | Audit and improve CLAUDE.md files | Claude plugin `claude-md-management@claude-plugins-official` |  |
| `claude-extensions` | [skill-creator](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/skill-creator) | Create, improve and evaluate skills | Claude plugin `skill-creator@claude-plugins-official` |  |
| `claude-extensions` | [frontend-design](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/frontend-design) | Production-grade frontend/UI design guidance | Claude plugin `frontend-design@claude-plugins-official` |  |
| `claude-extensions` | [document-skills](https://github.com/anthropics/skills) | Excel, Word, PowerPoint and PDF skills | Claude plugin `document-skills@anthropic-agent-skills` |  |
| `claude-extensions` | [scoop-windows](https://github.com/Heitorgkk/scoop-bucket/tree/main/claude/skills/scoop-windows) | Personal skill: how this machine installs tools (Scoop, Heitorgkk bucket, npm, WinGet) | Claude skill `claude/skills/scoop-windows` |  |
<!-- END GENERATED TOOLS TABLE -->

### Why some tools are not Scoop packages

| Tool | Decision | Reason |
|---|---|---|
| Claude Desktop | WinGet `Anthropic.Claude` | WinGet installs Anthropic's official signed installer from `downloads.claude.ai`. `extras/claude` repackages the old Squirrel `.nupkg`. Features that need the official install (Cowork) report *"requires a newer installation"* ([ScoopInstaller/Extras#18647](https://github.com/ScoopInstaller/Extras/issues/18647)), and its hash has broken on several releases. |
| ChatGPT Desktop | WinGet `OpenAI.ChatGPT` | WinGet installs the same signed MSIX that OpenAI publishes on `persistent.oaistatic.com` (it's also the Microsoft Store build). `extras/chatgpt` unpacks the MSIX and runs it *without package identity*. That made the app fail at startup ([ScoopInstaller/Extras#18777](https://github.com/ScoopInstaller/Extras/issues/18777)), and the workaround disables the app's own updater. |
| Gemini CLI | npm `@google/gemini-cli` | Google publishes it only on npm; there is no Scoop manifest. |
| Docker | Scoop `main/docker` | Installs the **Docker CLI and Docker Engine (`dockerd`) for Windows containers**. It is **not Docker Desktop** and cannot run Linux containers. The CLI can still talk to a remote, WSL or other Linux engine (`DOCKER_HOST`, `docker context`). `dockerd --register-service` needs an elevated shell and the Windows *Containers* feature. Docker Compose is a separate package (`main/docker-compose`). |
| OpenCode | Scoop `main/opencode` | This is the **CLI** (v2). The desktop app is `extras/opencode-desktop` and isn't included. v1 lives in `versions/opencode1`. |

### Scoop vs npm vs WinGet

| | Scoop | npm | WinGet |
|---|---|---|---|
| Used for | Most tools (21 of 24 apps) | Gemini CLI | Claude Desktop, ChatGPT Desktop |
| Install location | `~\scoop\apps\<app>` (portable, per user) | npm global prefix. With `main/nodejs-lts`: `~\scoop\persist\nodejs-lts\bin` (kept across Node updates) | Per-user MSIX / installer managed by Windows |
| Admin rights | No | No | No (per-user MSIX) |
| Update | `scoop update <app>` / `scoop update *` | `npm install -g @google/gemini-cli@latest` | `winget upgrade --id <id> --exact` |
| Uninstall | `scoop uninstall <app>` | `npm uninstall -g @google/gemini-cli` | `winget uninstall --id <id> --exact` |
| Without WinGet | n/a | n/a | Official signed MSIX via `Add-AppxPackage` (`-NoWinGet` or automatic fallback) |
| Tracked by a metapackage | Yes | No | No |

### Architecture support

Every package used here has a native x64 build. These have no ARM64 build:
`java/temurin-lts-jdk`, `main/docker` and `extras/sharex`. On Windows 11 ARM64, Scoop
installs their x64 builds, which run under x64 emulation. All other tools, and the WinGet/npm ones, ship native ARM64 builds.

### Notes per tool

- **rustup**: uses the MSVC toolchain by default, which needs the
  [Microsoft C++ Build Tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/)
  ("MSVC" and "Windows SDK" workloads). They aren't installed automatically because they
  are large and need admin rights. Run `rustup default stable` after installing.
- **jdk**: `temurin-lts-jdk` follows the latest Temurin LTS and sets `JAVA_HOME`.
- **claude-code**: needs Git Bash, which the `main` group provides.
- **oh-my-posh**: add it to your profile, for example
  `oh-my-posh init pwsh | Invoke-Expression`, and install a Nerd Font (`scoop bucket add nerd-fonts`).
- **Context menus / file associations** (7-Zip, Git, Everything, Windows Terminal, PowerToys) are
  not registered automatically. Each package prints the `reg import ...` command in its notes.

## Updating

```powershell
scoop update                      # refresh Scoop and all buckets (including Heitorgkk)
scoop update *                    # upgrade every Scoop app
scoop update all                  # re-sync a metapackage (installs tools added to the group)
.\scripts\install.ps1 -Group all -Update   # Scoop + npm + desktop apps + Claude plugins/skills in one go
claude plugin marketplace update claude-plugins-official; claude plugin update <plugin>@claude-plugins-official
```

Metapackages have no upstream version, so `checkver`/`autoupdate` don't apply to them.
Their version is bumped by hand when a group changes. The packages they depend on are
updated by the official buckets.

## Repository layout

```text
scoop-bucket/
├── bucket/                 # Scoop manifests (generated from groups.json)
│   ├── main.json  ai.json  terminal.json  utilities.json  claude-extensions.json  all.json
├── groups.json             # single source of truth: groups, tools, sources, buckets, marketplaces
├── setup.ps1               # one-line installer for a bare machine
├── claude/skills/          # personal Claude Code skills installed by the claude-extensions group
├── .claude/skills/add-tool # project skill: how to add a tool to this repository
├── meta/metapackage.txt    # tiny fixed payload downloaded by every metapackage
├── scripts/
│   ├── bootstrap.ps1
│   ├── install.ps1
│   ├── status.ps1
│   └── lib/                # Common.ps1 (catalog, Scoop, PATH), Tools.ps1 (per-source install/detect)
├── tools/catalog.py        # generate + validate bucket/ and the README table
├── tests/                  # script tests and CI helpers
└── .github/workflows/validate.yml
```

Why there's a payload file: Scoop refuses to install a manifest that has no `url`
(*"doesn't support current architecture"*). So each metapackage downloads
`meta/metapackage.txt` (a few hundred bytes, SHA256-pinned) from this repository's default
branch. Don't edit that file; if you have to, run `python tools/catalog.py generate` so the
hash is updated.

## Adding a tool

1. Find the exact manifest name in the official buckets
   (`scoop search <name>`, or browse Main/Extras/Java on GitHub).
2. Add an entry to the right group in [`groups.json`](groups.json):

   ```json
   {
       "name": "jq",
       "source": "scoop",
       "package": "main/jq",
       "command": "jq",
       "summary": "Command-line JSON processor",
       "homepage": "https://jqlang.github.io/jq/"
   }
   ```

   - `source`: `scoop` (`package` = `bucket/app`, always explicit), `npm` (`package` = npm
     name), `winget` (`package` = WinGet id), `claude-plugin` (`package` = `plugin@marketplace`)
     or `claude-skill` (`package` = `claude/skills/<name>`).
   - For `winget` apps, add a `direct` block (`type: msix`, `url.x64`/`url.arm64`, `appxName`,
     `signer`) with the vendor's stable "latest" MSIX URL, so the app also installs without WinGet.
   - Optional: `requirements` (shown in the README), `requires` (Scoop packages that must
     exist first, for example `["main/nodejs-lts"]` for npm tools).
   - A new official bucket must also be added to `buckets`.
3. Regenerate and validate:

   ```powershell
   python tools/catalog.py generate
   python -m pip install jsonschema
   python tools/catalog.py validate
   ```

4. Bump `METAPACKAGE_VERSION` in `tools/catalog.py` when the dependencies of a group change,
   so `scoop update <group>` notices the change.

A new group is just another key under `groups` (lowercase). Add it to `all.includes` too;
the validator fails if `all` doesn't cover every group.

## Validation & CI

[`.github/workflows/validate.yml`](.github/workflows/validate.yml) runs on every push and pull request, and weekly:

- **Manifests & catalog**: JSON syntax; `bucket/*.json` and this README in sync with
  `groups.json`; the official [Scoop schema](https://github.com/ScoopInstaller/Scoop/blob/master/schema.json);
  every referenced package exists in its official bucket; the npm package exists; no tool or package is
  declared twice; explicit `bucket/package` references to declared buckets only; no include cycles; `all`
  covers every group; the payload hash matches.
- **PowerShell lint**: PSScriptAnalyzer.
- **Script tests**: `tests/Test-Scripts.ps1` (invalid/valid arguments, exit codes, dry runs) under
  PowerShell 7 and Windows PowerShell 5.1.
- **Real installs on a Windows runner**:
  - `scoop install Heitorgkk/all` from a clean Scoop, then a no-op re-run and `scoop update all`.
  - `install.ps1 -Group ai,terminal` (Scoop + npm + WinGet) under Windows PowerShell 5.1, then a second
    run and `-Update`.
  - `setup.ps1` (run as a script block, the way `irm | iex` runs it) with `-NoWinGet -Group ai,claude-extensions`
    under PowerShell 7. It checks that both apps are MSIX packages and that the plugins and skill are
    installed, then runs `status.ps1`, a second run and `-Update`.
- The plugin names are checked against each marketplace's `marketplace.json`, and each direct MSIX URL must respond.

Locally:

```powershell
python tools/catalog.py check        # offline
.\tests\Test-Scripts.ps1             # nothing gets installed
```

## Contributing

1. Fork the repository, create a branch, edit `groups.json`. Edit scripts only when you need to.
2. Run `python tools/catalog.py generate` and commit the regenerated files.
3. Make sure `python tools/catalog.py validate` and `.\tests\Test-Scripts.ps1` pass.
4. Open a pull request that explains where the package comes from (official bucket, npm, or WinGet id).
   Prefer an existing official manifest over writing a new one.

## License

[Unlicense](LICENSE). The tools installed by this bucket keep their own licenses.
