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

The harness opens with the coffee mark, your current brief, and an `fmc>` prompt. Use slash commands to update local context. Bare text goes to the configured AI runner.

```text
/capture TEXT   Save work or an idea
/focus TEXT     Set the current outcome
/today          Show focus and open work
/done ID        Complete an open item
/ask TEXT       Ask the configured AI runner
/prompt TEXT    Print the prompt without invoking AI
/ping           Check in with FMC HQ
/doctor         Check local and server health
/help           Show commands
/quit           Close the session
```

When standard input or output is piped, the no-argument command prints the daily brief instead of opening a prompt. `founder-mode-coffee interactive` starts the harness explicitly.

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
capture TEXT           Save a task, idea, or commitment locally
focus set TEXT          Set the current outcome
focus show              Print the current outcome
focus clear             Clear the current outcome
today [--json]          Show the current focus and open work
done ID                 Complete and archive an open item
prompt TEXT             Build an AI prompt from current context
ask TEXT                Send current context to an AI runner
hello                   Show the Founder Mode Coffee welcome
ping                    Check in with FMC HQ
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

API configuration remains under:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/founder-mode-coffee/config
```

Configure a local or alternate Founder Mode Coffee API:

```bash
founder-mode-coffee config set api http://localhost:3001/api
founder-mode-coffee config get api
founder-mode-coffee config reset
```

`FMC_API` overrides the saved endpoint for one command.

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

The runtime needs Bash and curl. Tests use Python to validate JSON.

```bash
bash -n founder-mode-coffee tests/test_cli.sh tests/fixtures/curl
tests/test_cli.sh
shellcheck founder-mode-coffee tests/test_cli.sh tests/fixtures/curl
```

The test suite isolates configuration and productivity data in temporary directories. Network behavior uses a local curl fixture.
