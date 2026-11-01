# setup-mac

One script that sets up a fresh Mac (Apple Silicon) with my usual tools and config.

```bash
bash setup-mac.sh
```

Run it in Terminal, not piped, because it asks questions on the terminal.

## How it behaves

- **Safe to re-run.** Each step checks whether the thing is already installed and skips it if so.
- **Steps are independent.** A failed step does not stop the rest. A summary at the end lists what was done, skipped and failed.
- **Asks before overwriting config.** If `~/.zshrc` or `~/.ssh/config` already exists, you choose `[o]verwrite` or `[s]kip`. Overwrite keeps a backup at `<file>.bak.<timestamp>`. With no terminal available, it skips.
- **Logs everything.** The full run is saved to `~/Yashu/additionals/setup-mac.<timestamp>.log`. The log contains terminal colour codes, so view it with `cat`.

## What it installs

| Area | Items |
| --- | --- |
| Base | Xcode Command Line Tools, Homebrew |
| Git | Git, plus global aliases and `push.autoSetupRemote` |
| Docker | Docker Desktop, then pulls `mysql:8.0`, `postgres:16`, `redis`, `mongo`, `neo4j` |
| CLI tools | Ollama, cloudflared, AWS CLI, Python (Homebrew) |
| Shell | Oh My Zsh, zsh-syntax-highlighting, nvm and Node LTS, uv, Claude Code CLI |
| Config | `~/.ssh/config` (three hosts, one via cloudflared), `~/.zshrc` |
| Apps | Google Chrome, Brave, VS Code (direct download), Postman (Homebrew cask) |
| Cleanup | `brew cleanup --prune=all --scrub` |

## Git aliases

Set globally by the script (`git config --global alias.<name>`), along with `push.autoSetupRemote`.

| Alias | Runs | What it does |
| --- | --- | --- |
| `git cbs <name>` | `git branch <name> && git switch <name>` | Create a branch and switch to it |
| `git sp <name>` | `git switch <name> && git pull` | Switch to a branch and pull |
| `git co` | `checkout` | Short for checkout |
| `git fa` | `fetch --all` | Fetch from all remotes |
| `git cm "msg"` | `commit -m` | Commit with a message |
| `git amend` | `commit --amend --no-edit` | Add staged changes to the last commit, keep its message |
| `git fpwl` | `push --force-with-lease` | Safer force push |
| `git fp` | `push -f` | Force push (use `fpwl` where you can) |
| `git s` | `stash` | Short for stash |
| `git hr` | `reset --hard` | Hard reset |
| `git bl` | `for-each-ref` sorted by author date | List local branches, most recently committed first |
| `git ls` | `log` with custom format | One line per commit: hash, date, refs, subject, author |
| `git ll` | same as `ls`, plus `--numstat` | Like `ls`, with lines added/removed per file |
| `git pull` | `pull --rebase` | `pull` always rebases |

## Downloaded apps

Chrome, Brave and VS Code are downloaded into `~/Yashu/additionals/<app>/` and copied to `/Applications`.

- The download URLs are "latest", so there is no fixed checksum to compare against. The script saves the SHA-256 next to the file as `<file>.sha256`.
- Before installing, it verifies the code signature (`codesign`) and Gatekeeper acceptance (`spctl`). If either fails, the app is not installed.
- An app that is already in `/Applications` is skipped and never updated.

Homebrew cask installs write an `installed.txt` (app, version, source, paths) to `~/Yashu/additionals/<cask>/`.

## Notes

- Docker images need the daemon running. If it is down, the script starts Docker Desktop and waits up to 5 minutes (you may need to accept the licence dialog).
- Paths assume Apple Silicon (`/opt/homebrew`).
- After the run, open a new terminal or run `source ~/.zshrc`.
