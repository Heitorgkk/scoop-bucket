# After the install

`setup.ps1` opens this page when it finishes. Most tools work right away. A few need a one-time step from you,
and the checklist below covers them. Skip the sections for groups you did not install.

> **First:** close every terminal and open a new one, so the new `PATH` applies everywhere.
> Check that everything is in place with:
>
> ```powershell
> & "$env:USERPROFILE\scoop\buckets\Heitorgkk\scripts\status.ps1" -Group all
> ```

## Checklist

### 1. Git and GitHub (`main`)

```powershell
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
git config --global init.defaultBranch main
gh auth login            # GitHub CLI: pick GitHub.com > HTTPS > login with a web browser
gh auth setup-git        # let git use the gh credentials
```

### 2. Sign in to the AI tools (`ai`)

| Tool | How to sign in |
|---|---|
| Claude Code | run `claude`, then type `/login` |
| Codex | run `codex` and pick **Sign in with ChatGPT** |
| Gemini CLI | run `gemini` and pick **Login with Google** |
| OpenCode | `opencode auth login` |
| Claude / ChatGPT desktop | open them from the Start menu and sign in |

### 3. Prompt: Oh My Posh + a Nerd Font (`terminal`)

```powershell
oh-my-posh font install meslo          # installs MesloLGM Nerd Font for your user
notepad $PROFILE                        # creates the file if Notepad asks
```

Add this line to the profile, save, and open a new terminal:

```powershell
oh-my-posh init pwsh | Invoke-Expression
```

Then in **Windows Terminal → Settings → Defaults → Appearance → Font face**, choose `MesloLGM Nerd Font`.
For another look, pick a theme at <https://ohmyposh.dev/docs/themes> and add `--config <theme name or URL>`
after `init pwsh`.

> If `notepad $PROFILE` complains that the folder is missing: `New-Item -ItemType File -Force $PROFILE`.

### 4. Windows Terminal (`terminal`)

- **Settings → Startup → Default terminal application:** Windows Terminal.
- **Settings → Startup → Default profile:** PowerShell (or PowerShell 7 if you use it).
- For an "Open in Terminal" entry in Explorer's right-click menu, read the notes in `scoop info windows-terminal`.

### 5. Shell extras (`terminal`, optional)

Add these to `$PROFILE` too, if you like them:

```powershell
Set-Alias cat bat -Option AllScope              # bat instead of Get-Content for reading files
Set-PSReadLineOption -PredictionSource History  # suggestions from your history
fastfetch                                       # system summary when the shell opens
```

For `Ctrl+R` / `Ctrl+T` history and file search with fzf: `Install-Module PSFzf -Scope CurrentUser`, then add
`Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'` to the profile.

### 6. Everything (`utilities`)

1. Open **Everything** once. It indexes your drives in a few seconds.
2. **Tools → Options → General:** tick **Start Everything on system startup** and **Everything Service**
   (the service lets it read NTFS without admin rights after setup; it needs one admin prompt).
   Without the service, tick **Run as administrator** or keep indexing folders only (**Indexes → Folders**).
3. Optional: **Tools → Options → Keyboard → Show window hotkey** (e.g. `Win+Alt+Space`).

### 7. PowerToys (`utilities`)

Open PowerToys and enable what you want. Good starters:

- **PowerToys Run / Command Palette** (`Alt+Space` or `Win+Alt+Space`): app launcher. A community
  Everything plugin lets it search the Everything index.
- **FancyZones** (window layouts), **Text Extractor** (`Win+Shift+T`, OCR anything on screen),
  **Color Picker** (`Win+Shift+C`), **Always On Top** (`Win+Ctrl+T`).
- **General → Run at startup.**

### 8. ShareX and LocalSend (`utilities`)

- **ShareX:** set your hotkeys (default `Print Screen`) and the **After capture** actions (copy to clipboard,
  save to a folder). Turn off automatic upload if you do not want it.
- **LocalSend:** the first start asks for firewall access. Allow it on **private** networks, or other devices cannot find you.

### 9. Developer runtimes (`main`)

- **Java:** Scoop sets `JAVA_HOME`. Check with `java -version`.
- **Rust:** `rustc --version`. Without Microsoft C++ Build Tools, the installer sets up the GNU toolchain with MSYS2.
  For the MSVC toolchain, install *Desktop development with C++* from the
  [Build Tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/) and run `rustup default stable-msvc`.
- **Docker:** only the CLI and `dockerd` for Windows containers. For Linux containers use Docker Desktop or
  a WSL engine, and point the CLI at it (`docker context`).

### 10. Claude Code extras (`claude-extensions`, `claude-tools`)

- Inside `claude`: `/plugin` lists the plugins, `/mcp` shows the MCP servers (headroom, context-mode), `/ctx-doctor` checks context-mode.
- In a project, `/graphify .` builds a knowledge graph of the code.
- `rtk gain` shows how many tokens RTK has saved.

## Keep everything up to date

```powershell
scoop update; scoop update *                          # every Scoop app
& "$env:USERPROFILE\scoop\buckets\Heitorgkk\scripts\install.ps1" -Group all -Update   # npm, uv, plugins, desktop apps too
scoop cleanup *                                       # delete old versions
```

New tools added to a group arrive with `scoop update <group>`, for example `scoop update all`.

## Other useful tips

- **Something is missing?** Re-run the same `irm ... | iex` command. Installed tools are skipped, so it only retries what failed.
- **Find an app:** `scoop search <name>`. Install one-off apps with `scoop install extras/<name>`.
- **Reset an app's shims:** `scoop reset <app>`.
- **Windows settings worth a look:** show file extensions and hidden files (**File Explorer → View → Show**),
  turn on **Developer Mode** (**Settings → System → For developers**), and set up **WSL** with `wsl --install` (needs admin).

## What was installed

<!-- BEGIN GENERATED TOOLS LIST (tools/catalog.py generate) -->

### Essential Development Tools (`main`)

| Tool | What it does | Source |
|---|---|---|
| [gh](https://cli.github.com/) | GitHub CLI | Scoop `main/gh` |
| [git](https://gitforwindows.org/) | Git for Windows (portable) | Scoop `main/git` |
| [nodejs](https://nodejs.org/) | Node.js, current LTS line (includes npm) | Scoop `main/nodejs-lts` |
| [jdk](https://adoptium.net/) | Eclipse Temurin JDK, latest LTS (sets JAVA_HOME) | Scoop `java/temurin-lts-jdk` |
| [rustup](https://rustup.rs/) | Rust toolchain manager (MSVC host by default) | Scoop `main/rustup` |
| [msys2](https://www.msys2.org/) | MSYS2 with the MINGW64 gcc toolchain, wired to rustup's stable-x86_64-pc-windows-gnu | Scoop `main/msys2` |
| [docker](https://www.docker.com/) | Docker CLI + Docker Engine (dockerd) for Windows containers. NOT Docker Desktop | Scoop `main/docker` |
| [vscode](https://code.visualstudio.com/) | Visual Studio Code editor (portable, per user) | Scoop `extras/vscode` |

### AI & Coding Agents (`ai`)

| Tool | What it does | Source |
|---|---|---|
| [claude-code](https://code.claude.com/) | Claude Code CLI (official Anthropic native binary) | Scoop `main/claude-code` |
| [claude-gui](https://claude.com/download) | Claude Desktop, official Anthropic installer | WinGet `Anthropic.Claude` or official MSIX |
| [gemini-cli](https://github.com/google-gemini/gemini-cli) | Google Gemini CLI (official npm package) | npm `@google/gemini-cli` |
| [codex](https://github.com/openai/codex) | OpenAI Codex CLI | Scoop `main/codex` |
| [chatgpt-gui](https://chatgpt.com/download) | ChatGPT Desktop, official OpenAI MSIX | WinGet `OpenAI.ChatGPT` or official MSIX |
| [opencode](https://opencode.ai/) | OpenCode CLI (v2; not the desktop app) | Scoop `main/opencode` |

### Terminal & CLI (`terminal`)

| Tool | What it does | Source |
|---|---|---|
| [windows-terminal](https://github.com/microsoft/terminal) | Windows Terminal (portable) | Scoop `extras/windows-terminal` |
| [oh-my-posh](https://ohmyposh.dev/) | Prompt theme engine | Scoop `main/oh-my-posh` |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | Fast recursive text search | Scoop `main/ripgrep` |
| [fastfetch](https://github.com/fastfetch-cli/fastfetch) | System information tool | Scoop `main/fastfetch` |
| [fzf](https://github.com/junegunn/fzf) | Command-line fuzzy finder | Scoop `main/fzf` |
| [bat](https://github.com/sharkdp/bat) | cat clone with syntax highlighting | Scoop `main/bat` |
| [lazygit](https://github.com/jesseduffield/lazygit) | Terminal UI for git | Scoop `extras/lazygit` |

### Windows Utilities (`utilities`)

| Tool | What it does | Source |
|---|---|---|
| [everything](https://www.voidtools.com/) | Instant file search by name | Scoop `extras/everything` |
| [powertoys](https://github.com/microsoft/PowerToys) | Microsoft PowerToys | Scoop `extras/powertoys` |
| [sharex](https://getsharex.com/) | Screenshot and screen capture | Scoop `extras/sharex` |
| [7zip](https://www.7-zip.org/) | File archiver | Scoop `main/7zip` |
| [localsend](https://localsend.org/) | Local network file sharing | Scoop `extras/localsend` |

### Claude Code Plugins & Skills (`claude-extensions`)

| Tool | What it does | Source |
|---|---|---|
| [commit-commands](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/commit-commands) | Slash commands for commit, push and PR workflows | Claude plugin `commit-commands@claude-plugins-official` |
| [feature-dev](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/feature-dev) | Guided feature development with explorer/architect/reviewer agents | Claude plugin `feature-dev@claude-plugins-official` |
| [code-review](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/code-review) | Multi-agent pull request review | Claude plugin `code-review@claude-plugins-official` |
| [pr-review-toolkit](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/pr-review-toolkit) | Specialised PR review agents (tests, errors, types, comments) | Claude plugin `pr-review-toolkit@claude-plugins-official` |
| [security-guidance](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/security-guidance) | Security warnings and review for edited code | Claude plugin `security-guidance@claude-plugins-official` |
| [claude-md-management](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/claude-md-management) | Audit and improve CLAUDE.md files | Claude plugin `claude-md-management@claude-plugins-official` |
| [skill-creator](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/skill-creator) | Create, improve and evaluate skills | Claude plugin `skill-creator@claude-plugins-official` |
| [frontend-design](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/frontend-design) | Production-grade frontend/UI design guidance | Claude plugin `frontend-design@claude-plugins-official` |
| [document-skills](https://github.com/anthropics/skills) | Excel, Word, PowerPoint and PDF skills | Claude plugin `document-skills@anthropic-agent-skills` |
| [scoop-windows](https://github.com/Heitorgkk/scoop-bucket/tree/main/claude/skills/scoop-windows) | Personal skill: how this machine installs tools (Scoop, Heitorgkk bucket, npm, WinGet) | Claude skill `claude/skills/scoop-windows` |

### Claude Code Token & Context Tools (`claude-tools`)

| Tool | What it does | Source |
|---|---|---|
| [uv](https://docs.astral.sh/uv/) | Python package and tool manager (installs Graphify and Headroom, and Python 3.13) | Scoop `main/uv` |
| [rtk](https://www.rtk-ai.app/) | RTK: rewrites shell commands to cut LLM token use; global Claude Code hook via 'rtk init -g' | Scoop `main/rtk` |
| [graphify](https://github.com/Graphify-Labs/graphify) | Graphify: code knowledge graph for agents; installs its Claude Code skill ('graphify install') | uv tool `graphifyy` |
| [headroom](https://github.com/headroomlabs-ai/headroom) | Headroom: context compression; registers its MCP server in Claude Code ('headroom mcp install') | uv tool `headroom-ai[mcp]` |
| [ponytail](https://github.com/DietrichGebert/ponytail) | Ponytail: 'lazy senior dev' mode (YAGNI, stdlib first, smallest working change) | Claude plugin `ponytail@ponytail` |
| [context-mode](https://github.com/mksglu/context-mode) | Context Mode: sandboxed execution, FTS5 search and session continuity to save context | Claude plugin `context-mode@context-mode` |

<!-- END GENERATED TOOLS LIST -->
