# Contributing

Thanks for helping improve `unity-licensing-mode`.

## Before opening an issue or pull request

- Read the [README](README.md), [support guidance](SUPPORT.md), and [security policy](SECURITY.md).
- Keep changes small and preserve the existing command and configuration contract unless a breaking change is explicitly documented.
- Add or update fixture-based tests for behavior and failure paths.
- Run the checks listed below and inspect `git diff --check`.
- Never include `config/local.conf`, `runtime/`, Unity license files, private server URLs, network identifiers, tokens, or unredacted logs.

## Local checks

```sh
bash -n bin/unity-licensing-mode
bash tests/test-command.sh
bash tests/test-fixtures.sh
bash tests/test-release.sh
```

If ShellCheck is installed, also run:

```sh
shellcheck bin/unity-licensing-mode tests/*.sh
```

Real Unity, administrator, ZeroTier, and licensing-server validation must be performed in an authorized controlled environment. Tests in this repository must not require any of them.
