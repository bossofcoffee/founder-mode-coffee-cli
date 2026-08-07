# Changelog

## 2.2.0

- Added an interactive founder harness with safe slash-command routing.
- Added a terminal-safe Founder Mode Coffee ASCII mark.
- Made no-argument terminal launches interactive while preserving brief output in pipelines.
- Added bare-text AI handoff through the configured runner.
- Added interactive help and shell completion discovery.

## 2.1.0

- Added a local productivity loop with `capture`, `focus`, `today`, and `done`.
- Changed the default command from the welcome screen to the daily brief; `hello` remains available.
- Added JSON output for the daily brief.
- Added `prompt` to generate AI-ready context without calling a model.
- Added `ask` with a safe custom-runner contract and a Hermes Agent adapter.
- Added atomic item claims so concurrent captures retain unique IDs.
- Added XDG data storage separate from API configuration.

## 2.0.0

- Added subcommands with focused help and consistent exit codes.
- Added JSON output for `ping`, `status`, `doctor`, and `update`.
- Added XDG configuration with `FMC_API` environment override.
- Added a `doctor` command for local and API diagnostics.
- Added completion generation for Bash, Zsh, and Fish.
- Added update checks against GitHub releases.
- Added `NO_COLOR` and `--no-color` support.
- Added network timeouts and structured errors.
- Added functional tests and continuous integration.
