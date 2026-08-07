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

Future changes will be listed here before the next versioned release.
