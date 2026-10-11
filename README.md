# Founder Mode Coffee CLI

Founder Mode Coffee CLI is a local operating loop for founders. Capture loose work, choose the outcome that matters now, clear completed items, and give the same context to an AI runner when you want a second brain.

The productivity workflow stays on your machine. The CLI reaches the network only when you run a network command such as `ping`, `doctor`, `update`, or an AI runner through `ask`.

## Install

```bash
curl -fsSL https://foundermodecoffee.com/install.sh | bash
```

Launch the interactive harness in a terminal:

```bash
founder-mode-coffee
```

The harness opens with the coffee mark, your current brief, and an amber `fmc>` prompt. Built-in commands work with or without a leading slash. Unrecognized text goes to the configured AI runner; `ask TEXT` always goes to AI, even when TEXT starts with a command word. Input is literal text, not shell code: quotes, substitutions, and semicolons are not evaluated.

```text
capture TEXT    Save work or an idea
focus set TEXT  Set the current outcome (focus TEXT also works)
focus show      Show the current outcome
today           Show focus and open work
done ID         Complete an open item
ask TEXT        Ask the configured AI runner, bypassing command recognition
prompt TEXT     Print the prompt without invoking AI
network         Refresh presence once, then show network counts
online          Stay online during this session
offline         Stop heartbeats and remove the online lease
status          Show local CLI setup
ping            Probe FMC HQ without joining
doctor          Check local and server health
help            Show commands (/help still works)
quit            Close the session (/quit still works)
```

When standard input or output is piped, the no-argument command prints the daily brief instead of opening a prompt. `founder-mode-coffee interactive` starts the harness explicitly.

## FMC network

```bash
founder-mode-coffee network        # refresh presence once, then read aggregate counts
founder-mode-coffee online         # interactive session with quiet heartbeats
founder-mode-coffee offline        # remove the installation's online lease
founder-mode-coffee checkin        # explicitly check in this installation
founder-mode-coffee me             # your private check-in history
founder-mode-coffee net            # local interface, gateway and IPv4 address
founder-mode-coffee network --json # clean output for scripts
```

The same commands work as bare words or slash aliases in the interactive terminal. Startup and `hello` show the ASCII coffee logo; one-shot JSON and piped daily briefs never include a banner.

Online means presence confirmed within the last 300 seconds. Counts represent anonymous CLI installations, not verified people. Opening the CLI does not join the network. Explicit `network` refreshes presence once before reading aggregate counts; it does not start a heartbeat. `online` registers presence successfully before entering continuous mode, then sends quiet heartbeats every 60 seconds while you edit input. The first presence registers membership and one check-in; subsequent heartbeats do not increase check-in counters.

An online session's prompt, banner on redraw, and accent turn green only while its last confirmed lease is fresh. A failed initial registration remains amber and does not start a worker. During an outage the worker stays silent, availability is reported on subsequent commands, and green expires with the last confirmed lease. The prompt is reevaluated between commands, never by interrupting a partially typed line. `offline` stops the worker first, attempts to remove the lease, and returns to local amber even if the server is unavailable. Quit, EOF, Ctrl-C, and TERM clean up the session and attempt an offline request with a two-second timeout. Membership and counters remain. SIGKILL or loss of connectivity cannot guarantee remote removal; the lease expires naturally.

`founder-mode-coffee online --json` is a one-shot presence registration, not an interactive session or daemon. It emits only the presence contract. `network --json` emits only aggregate JSON after successful presence registration. HTTP 503/429, connection errors, and invalid contracts return nonzero JSON errors, never fabricated counts. Interactive sessions keep their normal prompt and banner even when an individual command requests JSON.

The first explicit `checkin`, `network`, or `online` creates a random private identity in `$XDG_CONFIG_HOME/founder-mode-coffee/identity` (default `~/.config/founder-mode-coffee/identity`). It is stored with mode 0600 and sent as a bearer credential through curl's stdin configuration, never process arguments. Presence requests do not follow authenticated redirects. Do not share this file. Losing it creates a new installation identity; there is no account recovery. No email, task content, hostname, or location is included. Hosting providers still receive normal connection metadata. `net` reads the local routing configuration without scanning devices or requesting a public IP.

Network stats require the website's durable Redis backend. Unconfigured or unavailable services return an error, never invented zeroes. `ping` remains a connectivity probe and does not register a user.

## Updating

```bash
founder-mode-coffee update --check
founder-mode-coffee update --install
```

`update` and `update --json` retain their existing read-only release-check behavior. `--install` is explicit: it downloads the exact release archive and its `.tar.gz.sha256` sidecar from the official repository, verifies SHA-256, archive members, shell syntax and reported version, then atomically replaces the invoked executable. Failure leaves the previous CLI intact. Current or older releases never downgrade the installation. Symlinks/Homebrew packages and source checkouts are not overwritten; use the package manager or website installer instead. No sudo or shell-profile editing is performed.

Release maintainers must upload both `founder-mode-coffee-VERSION.tar.gz` and `founder-mode-coffee-VERSION.tar.gz.sha256`. Beginning with v2.3.0, release archives include checksum sidecars for verified self-updates. Older v2.2.1 installations only support update checks; use the website installer to upgrade them. Update the website installer's pinned version, URL and real checksum together after publishing each release.

## The operating loop

Capture something before it gets lost:

```bash
founder-mode-coffee capture "Send the supplier note"
founder-mode-coffee capture "Review the launch page"
```

Choose the current outcome:

```bash
founder-mode-coffee focus set "Publish the launch page"
```

Open the brief:

```text
$ founder-mode-coffee
FOCUS  Publish the launch page

OPEN
  [1] Send the supplier note
  [2] Review the launch page
```

Complete work without deleting its local record:

```bash
founder-mode-coffee done 1
founder-mode-coffee focus clear
```

## AI harness

`prompt` creates a complete request from the current focus, open work, and your question. It does not call a model:

```bash
founder-mode-coffee prompt "What should I do next?"
```

`ask` sends that prompt to a configured runner. Hermes Agent has a built-in adapter:

```bash
FMC_AI_RUNNER=hermes founder-mode-coffee ask "What should I do next?"
```

For another provider or local model, set `FMC_AI_RUNNER` to one executable. The CLI sends the prompt on standard input and preserves the runner's standard output:

```bash
FMC_AI_RUNNER="$HOME/bin/my-ai-runner" \
  founder-mode-coffee ask "Turn this into a two-hour work block"
```

The runner value is never evaluated as shell code and cannot contain arguments. Put provider-specific flags in a small wrapper executable instead.

## Commands

```text
interactive            Open the interactive founder harness
network                Refresh presence once and show aggregate counts
online                 Open an interactive online session
offline                Remove the online lease
capture TEXT           Save a task, idea, or commitment locally
focus set TEXT          Set the current outcome
focus show              Print the current outcome
focus clear             Clear the current outcome
today [--json]          Show the current focus and open work
done ID                 Complete and archive an open item
prompt TEXT             Build an AI prompt from current context
ask TEXT                Send current context to an AI runner
hello                   Show the Founder Mode Coffee welcome
ping                    Probe FMC HQ without registration
status                  Show the resolved local setup
doctor                  Check curl, configuration, and API access
config                  Read or change API configuration
completion              Generate completion for Bash, Zsh, or Fish
update                  Check the latest GitHub release
help [command]          Show focused help
```

Every command supports `--help`. Usage errors return exit code `2`; runtime and network failures return `1`.

## Structured output

The daily brief is available as JSON for scripts and agents:

```bash
founder-mode-coffee today --json
founder-mode-coffee --json today
```

```json
{"focus":"Publish the launch page","open":[{"id":2,"text":"Review the launch page"}]}
```

The existing network and status commands also support JSON:

```bash
founder-mode-coffee ping --json
founder-mode-coffee doctor --json
founder-mode-coffee --json status
```

## Local data

Productivity data follows the XDG base-directory convention:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/founder-mode-coffee/
```

Open items, completed items, and the current focus are stored as plain local files. `XDG_DATA_HOME` can isolate separate workspaces or test runs.

TTY sessions use native Bash readline (`read -e`) for Up/Down recall. Only submitted user lines enter history; internal script commands never do. History persists in `${XDG_DATA_HOME:-$HOME/.local/share}/founder-mode-coffee/.history/commands`, separate from your Bash history, with a 0700 directory and a 0600 file, capped at 500 entries. Piped input works without readline or history writes. Symlinks, hard-linked files, non-owned destinations, and unsafe permissions are refused rather than repaired. XDG paths for private history/identity must be absolute and symlink-free. History includes your submitted text; do not enter secrets. Simultaneous sessions have last-writer-wins history, not a merged log.

The heartbeat worker writes only a private timestamp and availability status to a temporary 0700 session directory; requests use short-lived private response files. Everything is removed on normal session cleanup. No system daemon, sudo, or shell-profile changes are needed.

API configuration remains under:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/founder-mode-coffee/config
```

Configure a local or alternate Founder Mode Coffee API:

```bash
founder-mode-coffee config set api http://127.0.0.1:3001/api
founder-mode-coffee config get api
founder-mode-coffee config reset
```

`FMC_API` overrides the saved endpoint for one command.

## Security boundaries

Off-host API, GitHub, and update requests require certificate-verified HTTPS, TLS 1.2 or newer, and HTTPS-only redirects. Every curl invocation disables `~/.curlrc` before other arguments. Plain HTTP is allowed only for the explicit literal loopback hosts `127.0.0.1` and `[::1]`; `localhost` is not accepted for HTTP. Authenticated requests never follow redirects, including redirects to another HTTPS host. Use the canonical `https://www.foundermodecoffee.com/api` endpoint. Custom endpoints receive your installation bearer when you explicitly use an authenticated network command, so choose them carefully.

Network output is restricted to the known contract. Identity status and timestamps are validated; untrusted error bodies are not printed, and reflected identity strings are redacted. Presence includes no commands, tasks, email, location, prompts, or runner output. The Hermes adapter uses `hermes chat --query-file -` with the exact prompt on stdin, not in process arguments. Starting the harness, reading the brief, or sending presence never invokes a runner; `ask` and submitted unrecognized interactive text explicitly invoke the configured runner.

Local files are plaintext, not encrypted at rest. Private identity/history and temporary files use owner-only permissions and link guards; these do not protect against root, malware running as your user, unencrypted backups, or physical access to an unlocked machine. Use OS full-disk encryption and appropriate backup protection. `FMC_NO_HISTORY=1` disables disk history while keeping session Up/Down recall; it does not disable saved tasks/focus or the runner's own logs. External runners control their own transport, storage, and integrations: the CLI does not claim that all integrations are encrypted.

## Shell completion

```bash
# Bash
source <(founder-mode-coffee completion bash)

# Zsh
source <(founder-mode-coffee completion zsh)

# Fish
founder-mode-coffee completion fish | source
```

## Color

Color is used only when output is attached to a terminal. Set `NO_COLOR` or pass `--no-color` to disable it.

## Development

The runtime needs Bash 3.2 or newer and curl, with the existing standard Unix utilities. Tests use Python 3's standard library for JSON, real PTYs (`pty`/`select`), and local HTTP/HTTPS fixtures; TLS tests generate clearly test-only certificates with OpenSSL. Backend end-to-end verification belongs to the website project.

```bash
for file in founder-mode-coffee tests/*.sh tests/fixtures/curl tests/update-fixtures/curl; do bash -n "$file"; done
bash tests/test_cli.sh
bash tests/test_network_ux.sh
bash tests/test_update_install.sh
python3 tests/test_interactive.py
python3 tests/test_secure_transport.py
python3 tests/test_security_regressions.py
python3 tests/test_tls.py
shellcheck founder-mode-coffee tests/*.sh tests/fixtures/curl tests/update-fixtures/curl
```

The test suite isolates configuration and productivity data in temporary directories. Legacy tests use curl fixtures; PTY tests use real curl against a local HTTP server. `FMC_TEST_HEARTBEAT_SECONDS` is a test-only interactive-session override accepting decimal integers 1–60 (no leading zeroes); the production default is 60 seconds. Lease expiry tests age the private timestamp rather than altering the production 300-second window. CI runs on Linux and macOS, including macOS's Bash 3.2.
