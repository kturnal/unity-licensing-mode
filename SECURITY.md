# Security policy

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability. Use GitHub's private vulnerability reporting for this repository when it is available. If it is unavailable, contact the repository maintainer privately through the contact listed in the repository owner profile.

Include a concise description, affected version or commit, reproduction steps that do not disclose credentials, and the likely impact. Redact all license files, tokens, private URLs, network identifiers, logs, and personal data.

## Sensitive data

Keep these values and files private:

- `config/local.conf`
- `runtime/` and installed state directories
- Unity license XML files and licensing logs
- private licensing-server URLs and network identifiers
- floating-lease return tokens

The helper reads tokens from stdin or an interactive prompt. By default it passes the captured token as the argument required by Unity.Licensing.Client, which may briefly expose it to process inspection. The positional token form remains only for compatibility and can additionally expose the token to shell history. Use `UNITY_LICENSE_CLI_MODE=stdin` only with a compatible custom wrapper.

This project does not activate licenses, operate a licensing server, join or authorize networks, or bypass Unity licensing.
