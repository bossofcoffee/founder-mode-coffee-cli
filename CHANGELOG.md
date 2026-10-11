# Changelog

## 2.4.0 (unreleased)

- Enforced verified off-host HTTPS, TLS 1.2 minimum, HTTPS-only redirects, and curlrc isolation.
- Rejected authenticated redirects and unsafe identity files; filtered network contracts and reflected credentials.
- Moved Hermes prompts from argv to exact stdin query-file input.
- Added optional memory-only session history and documented plaintext-at-rest/runner security boundaries.
- Added real TLS and in-flight PTY signal regressions with tracked child cleanup.

- Added native readline Up/Down history with a private, bounded local history file.
- Made built-in commands work without a slash; retained slash aliases and explicit AI escape via ask.
- Added opt-in online sessions with quiet 60-second presence heartbeats and lease-aware green styling.
- Added offline and session cleanup for quit, EOF, interrupt, and termination.
- Made network refresh presence before reading counts; JSON failures remain nonzero errors.
- Added real PTY/HTTP-fixture tests for history, privacy, input integrity, availability, and process cleanup.

## 2.3.0

- Added FMC network counts, explicit anonymous check-in, and private installation stats.
- Added local network diagnostics without device scanning or public-IP lookups.
- Added verified atomic self-updates with managed-install protection.
- Expanded the startup ASCII logo and interactive command discovery.
- Added network integration and update safety tests.

## 2.2.1

- Fixed `ping` against the production API by following the canonical HTTPS redirect.

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
