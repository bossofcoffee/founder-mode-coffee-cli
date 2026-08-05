# Founder Mode Coffee CLI

A small command line tool for Founder Mode Coffee. It checks in with the site, reports its setup, supports scripts with JSON output, and stays out of the way when used in a pipeline.

## Install

```bash
brew tap bossofcoffee/founder-mode-coffee
brew install founder-mode-coffee
```

Run the welcome:

```bash
founder-mode-coffee
```

## Commands

```text
hello                  Show the Founder Mode Coffee welcome
ping                   Check in with FMC HQ
status                 Show the resolved local setup
doctor                 Check curl, configuration, and API access
config                 Read or change configuration
completion             Generate completion for bash, zsh, or fish
update                 Check the latest GitHub release
help [command]          Show focused help
```

Every command supports `--help`. Network and status commands support `--json` for scripts:

```bash
founder-mode-coffee ping --json
founder-mode-coffee --json status
founder-mode-coffee doctor --json
```

Usage errors return exit code `2`. Runtime and network failures return `1`.

## Configuration

The CLI follows the XDG base-directory convention:

```bash
founder-mode-coffee config path
founder-mode-coffee config set api http://localhost:3001/api
founder-mode-coffee config get api
founder-mode-coffee config reset
```

`FMC_API` overrides the saved endpoint for one command:

```bash
FMC_API=http://localhost:3001/api founder-mode-coffee ping
```

Configuration precedence is:

1. `FMC_API`
2. The XDG config file
3. `https://foundermodecoffee.com/api`

## Shell completion

Bash:

```bash
source <(founder-mode-coffee completion bash)
```

Zsh:

```zsh
source <(founder-mode-coffee completion zsh)
```

Fish:

```fish
founder-mode-coffee completion fish | source
```

## Color

Color is used only when output is attached to a terminal. Set `NO_COLOR` or pass `--no-color` to disable it.

## Development

The runtime only needs Bash and curl. Tests also use Python to validate JSON.

```bash
bash -n founder-mode-coffee tests/test_cli.sh tests/fixtures/curl
tests/test_cli.sh
```

The test suite uses a local curl fixture and never changes production data.
