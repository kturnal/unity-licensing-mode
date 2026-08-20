# Support

Start with the redacted reports from:

```sh
./bin/unity-licensing-mode status
./bin/unity-licensing-mode doctor
```

For automation, use `status --json` or `doctor --json`. Do not attach the output of commands that print private paths or logs without reviewing it first.

For a useful bug report, include:

- the `unity-licensing-mode` version;
- macOS and Unity versions;
- the selected provider (`direct` or `zerotier`);
- redacted `doctor` output;
- the exact command and exit status.

Never include `config/local.conf`, `runtime/`, license files, private server URLs, network IDs, lease tokens, or unredacted Unity logs. Licensing, account, entitlement, and server-access questions belong with the administrator of the relevant Unity or licensing service.
