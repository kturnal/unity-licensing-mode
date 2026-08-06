# unity-licensing-mode

`unity-licensing-mode` is a small macOS command-line helper for switching Unity between:

- **Personal licensing**, using the local Unity account and entitlement path.
- **Floating licensing**, using an existing Unity floating-license configuration and a licensing server reachable through ZeroTier.

It closes Unity cleanly, stops the Unity Licensing Client, preserves configuration backups, and restores the selected licensing configuration.

This project does not bypass Unity licensing, provide a licensing server, store Unity credentials, or activate a license on your behalf. You must already have valid access to the Unity account, floating-license server, and ZeroTier network that you use.

## Contents

- [Quick start](#quick-start)
- [Requirements](#requirements)
- [Configuration](#configuration)
- [Commands](#commands)
- [How switching works](#how-switching-works)
- [Troubleshooting](#troubleshooting)
- [Security and privacy](#security-and-privacy)
- [Repository layout](#repository-layout)
- [Development](#development)
- [License and support](#license-and-support)

## Quick start

Clone the repository and create a private local configuration file:

```sh
git clone https://github.com/kturnal/unity-licensing-mode.git
cd unity-licensing-mode

cp config/example.conf config/local.conf
chmod 600 config/local.conf
${EDITOR:-vi} config/local.conf
```

Replace the placeholders in `config/local.conf` with the values for your own ZeroTier network and Unity floating-license server. Do not commit this file.

Check the current local state before changing modes:

```sh
./bin/unity-licensing-mode status
```

Use the command directly from the repository:

```sh
./bin/unity-licensing-mode personal
./bin/unity-licensing-mode floating
```

### Optional command shortcuts

To make the command available from any directory, create symlinks in `~/.local/bin`:

```sh
mkdir -p "$HOME/.local/bin"
ln -s "$PWD/bin/unity-licensing-mode" "$HOME/.local/bin/unity-licensing-mode"
ln -s "$PWD/bin/unity-licensing-mode" "$HOME/.local/bin/ulm"
export PATH="$HOME/.local/bin:$PATH"
```

The `ulm` name is only a shortcut; it runs the same script. Add the `PATH` export to your shell profile if you want it to persist across new terminal sessions.

## Requirements

| Requirement | Used by | Notes |
| --- | --- | --- |
| macOS | All commands | The script uses macOS paths, `osascript`, and `sudo`. |
| Unity Hub and Unity Editor | Mode changes | Save work before running a mode-changing command. |
| ZeroTier and `zerotier-cli` | `floating` and status reporting | The machine must be joined to the authorized licensing network. |
| Unity floating-license server | `floating` | The server and its licensing configuration must already exist. |
| `jq` | Optional floating verification | If installed, the endpoint in the active Unity config is checked against `UNITY_LICENSE_SERVER_URL`. |
| `unity-license` CLI | `return-floating` only | Defaults to `/usr/local/bin/unity-license`; configure another path when necessary. |

Commands that touch `/Library/Application Support/Unity` may request administrator privileges through `sudo`.

## Configuration

The public template is [`config/example.conf`](config/example.conf). Copy it to `config/local.conf` and protect it with mode `600`.

The configuration file uses simple `KEY="value"` entries and comments. It is parsed as data; it is not sourced as shell code.

| Setting | Required | Purpose | Default |
| --- | --- | --- | --- |
| `UNITY_ZEROTIER_NETWORK_ID` | `floating` | ZeroTier network ID used to find and configure the licensing network. | None |
| `UNITY_ZEROTIER_NETWORK_NAME` | `floating` | Human-readable network name used in status and error messages. | None |
| `UNITY_LICENSE_SERVER_URL` | `floating` | Expected Unity licensing-server endpoint. | None |
| `UNITY_LICENSE_CLI` | `return-floating` | Path to the local `unity-license` executable. | `/usr/local/bin/unity-license` |

These environment variables override the corresponding file values when set:

- `UNITY_ZEROTIER_NETWORK_ID`
- `UNITY_ZEROTIER_NETWORK_NAME`
- `UNITY_LICENSE_SERVER_URL`
- `UNITY_LICENSE_CLI`

The following environment-only controls are also supported:

| Variable | Purpose | Default |
| --- | --- | --- |
| `UNITY_LICENSING_MODE_CONFIG_FILE` | Use a configuration file at another path. | `config/local.conf` in this repository |
| `UNITY_LICENSING_MODE_STATE_DIR` | Store backups and the preserved floating template elsewhere. | `runtime/` in this repository |

## Commands

| Command | Behavior | Side effects and prerequisites |
| --- | --- | --- |
| `status` | Shows the configuration file, active Unity configs, backups, preserved template, local license files, licensing-client state, lease-file count, and ZeroTier state. | Read-only status checks. |
| `personal` | Disables active floating configuration files and leaves the local personal-license path available. | Closes Unity Hub/Editor and the licensing client; preserves backups. Sign in to Unity normally afterward. |
| `floating` | Restores the preserved floating template to the system Unity configuration and disables the user-level duplicate configuration. | Requires all floating settings, an existing floating template, an authorized ZeroTier network, and may require `sudo`. |
| `reload-client` | Stops the running Unity Licensing Client so it reloads the selected mode at the next Unity start. | Stops only the licensing client. |
| `return-floating <token>` | Returns a floating lease through the configured `unity-license` CLI. | Closes Unity and the licensing client. The token is sensitive; see [Security and privacy](#security-and-privacy). |

Run `./bin/unity-licensing-mode --help` for the command summary.

## How switching works

### Personal mode

`personal`:

1. Closes Unity Hub and the Unity Editor.
2. Stops the Unity Licensing Client.
3. Moves active Unity `services-config.json` files into timestamped managed backups.
4. Leaves the local personal-license path available.

The command does not sign in to Unity. After it completes, sign in with the Unity account you are authorized to use and open Unity normally.

### Floating mode

`floating`:

1. Verifies the required floating configuration values.
2. Closes Unity Hub and the Unity Editor.
3. Stops the Unity Licensing Client.
4. Preserves a floating configuration template if one is not already in `runtime/`.
5. Verifies that the machine is joined to the configured ZeroTier network.
6. Enables ZeroTier managed routes for that network when necessary.
7. Moves active user- and system-level Unity configuration files into managed backups.
8. Copies the preserved template to `/Library/Application Support/Unity/config/services-config.json`.
9. Verifies the licensing endpoint when `jq` is available.

The first floating-mode run does not construct a Unity `services-config.json` from the server URL. Unity must already have produced a floating configuration, or the command must be able to find one of its managed backups. If no template can be found, `floating` stops without installing a floating configuration; Unity may already have been closed as part of the preflight.

The script never deletes Unity configuration files. It moves active files into the managed state directory and keeps timestamped backups when a backup already exists.

## Troubleshooting

Start with a status report:

```sh
./bin/unity-licensing-mode status
```

### Configuration errors

- If `floating` reports a missing `UNITY_ZEROTIER_NETWORK_ID`, `UNITY_ZEROTIER_NETWORK_NAME`, or `UNITY_LICENSE_SERVER_URL`, fill in `config/local.conf` or provide the corresponding environment override.
- If `floating` reports that no Unity floating config can be preserved, configure Unity for floating licensing once, then retry. The tool restores an existing template; it does not create one.
- If `return-floating` reports that `unity-license` is missing, set `UNITY_LICENSE_CLI` to the path of an executable Unity license CLI.

### Unity process and permissions

- Save all Unity work before running `personal` or `floating`.
- If Unity Hub, the Editor, or the Licensing Client does not exit within the command timeout, close it manually and retry.
- Confirm that your macOS account can approve `sudo` when changing the system-level Unity configuration.

### ZeroTier and server reachability

Check that the machine is online and joined to the expected network:

```sh
zerotier-cli info
zerotier-cli listnetworks
```

`floating` can enable managed routes, but it cannot join or authorize a machine on a ZeroTier network. Ask the network administrator to authorize the machine if the network is missing or unavailable.

To separate routing from Unity lease acquisition, test the configured server independently:

```sh
LICENSE_SERVER_URL='http://your-license-server.example:1554'
route -n get your-license-server.example
curl --connect-timeout 5 "$LICENSE_SERVER_URL"
```

Replace the example host, port, and URL with your private server values. A successful HTTP response proves server reachability only; it does not prove that Unity acquired a floating lease.

### Unity licensing logs and lease state

Inspect the Unity Licensing Client log at:

```text
~/Library/Logs/Unity/Unity.Licensing.Client.log
```

Look for messages about the active licensing mode, endpoint, route failures, or lease acquisition. `status` also reports the personal entitlement file and other XML lease files under `~/Library/Unity/licenses`. A personal entitlement file alone does not prove that a floating lease was acquired.

## Security and privacy

Keep these files and values private:

- `config/local.conf`
- `runtime/`
- Unity license XML files
- Unity licensing logs
- private licensing-server URLs
- private network identifiers
- floating-license return tokens

The local configuration and runtime state are ignored by Git. Review `git status --ignored` before publishing changes or sharing diagnostics.

`return-floating <token>` passes the token as a command-line argument. Depending on the shell and operating system, command arguments can appear in shell history or process inspection. Do not paste tokens into issues, chat, screenshots, or terminal transcripts.

This project is independent of Unity Technologies. Unity, Unity Hub, Unity Editor, and related names are trademarks of their respective owners. Use this tool only with licenses, accounts, networks, and servers you are authorized to use.

## Repository layout

```text
bin/unity-licensing-mode   # Executable command
config/example.conf        # Public configuration template
tests/test-command.sh       # Syntax and command-dispatch checks
LICENSE                     # MIT license
README.md                   # This documentation

config/local.conf           # Local only; ignored by Git
runtime/                    # Local backups and floating template; ignored by Git
```

The local-only paths are intentionally absent from the public repository.

## Development

Run the lightweight checks from the repository root:

```sh
bash -n bin/unity-licensing-mode
bash tests/test-command.sh
```

These checks validate shell syntax, help output, supported command dispatch, and rejection of unsupported commands. They do not exercise real Unity, ZeroTier, sudo, server, or floating-lease operations.

When opening an issue or pull request, include the macOS and Unity versions plus redacted command output where useful. Never attach `config/local.conf`, `runtime/`, license files, unredacted logs, server URLs, network identifiers, or lease tokens.

## License and support

This project is released under the [MIT License](LICENSE).

For bugs or improvements, open a GitHub issue with a minimal, redacted reproduction. For licensing, account, server, or entitlement problems, contact the administrator of the relevant Unity or ZeroTier service.
