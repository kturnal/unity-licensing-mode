# Changelog

All notable changes to `unity-licensing-mode` are documented here.

## [0.1.0] - 2026-08-06

The first maintained public release.

- Added `VERSION`, `version`, and `--version` with one release source of truth.
- Added redacted `status --json` and read-only `doctor` diagnostics.
- Added `--dry-run` for every mode-changing command.
- Added process-safe operation locking, transaction metadata, and configuration rollback.
- Added mandatory `jq` validation and endpoint-aware floating-template selection.
- Added stdin and interactive token input for floating-lease returns.
- Added package-safe configuration and state defaults for macOS and Linux.
- Added fixture-based Bash coverage, ShellCheck CI, and public-repository contribution files.

Release tags use the immutable `vMAJOR.MINOR.PATCH` form and must match `VERSION`.

## Unreleased

- Fixed the operation lock so a lock left behind by a process that is no
  longer running (a crash, a killed terminal) is detected as stale and
  cleared automatically instead of permanently blocking every future
  command with "Another unity-licensing-mode operation already holds the
  lock." `doctor` now reports a stale lock distinctly from a genuinely held
  one. Incomplete lock metadata left by an interruption is also recoverable
  after a short grace period.
