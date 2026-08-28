# unity-licensing-mode

unity-licensing-mode is a macOS command-line helper for switching Unity
between:

- **Personal licensing**, using the local Unity account and entitlement path.
- **Floating licensing**, using an existing Unity floating-license
  configuration and either an existing operating-system route or ZeroTier.

Version 0.1.0 adds read-only diagnostics, safe previews, endpoint-validated
configuration selection, operation locks, transaction metadata, and rollback.

This project does not bypass Unity licensing, provide a licensing server, store
Unity credentials, or activate a license on your behalf. You must already have
valid access to the Unity account, floating-license server, and network that you
use.

## Quick start

From a source checkout:

~~~
git clone https://github.com/kturnal/unity-licensing-mode.git
cd unity-licensing-mode

cp config/example.conf config/local.conf
chmod 600 config/local.conf
vi config/local.conf
~~~

Check the current state before changing modes:

~~~
./bin/unity-licensing-mode status
./bin/unity-licensing-mode doctor
~~~

Preview a change first:

~~~
./bin/unity-licensing-mode --dry-run personal
./bin/unity-licensing-mode --dry-run floating
~~~

Then switch modes:

~~~
./bin/unity-licensing-mode personal
./bin/unity-licensing-mode floating
~~~

The command also works as ulm when the executable is symlinked into a
directory on PATH.

## Requirements

| Requirement | Used by | Notes |
| --- | --- | --- |
| macOS | Mode-changing commands | Unity process and system configuration handling currently targets macOS. |
| Unity Hub and Unity Editor | Mode changes | Save work before running personal or floating. |
| jq | floating, template checks, and doctor validation | Floating JSON validation is mandatory in 0.1.0. |
| curl | Server reachability in doctor | The check is bounded and its output is suppressed. |
| ZeroTier and zerotier-cli | floating with the zerotier provider | The machine must already be joined and authorized. |
| Unity license CLI | return-floating | Configure its path with UNITY_LICENSE_CLI. |

Commands that touch /Library/Application Support/Unity may request
administrator privileges through sudo. The tool never joins or authorizes a
network.

## Configuration

The public template is config/example.conf. Copy it to config/local.conf and
protect it with mode 600.

| Setting | Required | Purpose | Default |
| --- | --- | --- | --- |
| UNITY_NETWORK_PROVIDER | floating | direct for an existing route or zerotier for ZeroTier. | zerotier |
| UNITY_NETWORK_ID | floating with ZeroTier | ZeroTier network ID. | None |
| UNITY_NETWORK_NAME | floating with ZeroTier | Human-readable local label. | None |
| UNITY_NETWORK_ALLOW_CHANGES | floating with ZeroTier | Opts in to joining the configured ZeroTier network and enabling its managed routes. | false |
| UNITY_LICENSE_SERVER_URL | floating | Expected http:// or https:// endpoint. | None |
| UNITY_LICENSE_CLI | return-floating | Path to the local Unity license CLI. | /usr/local/bin/unity-license |
| UNITY_LICENSE_CLI_MODE | return-floating | stdin keeps the token out of process arguments; argument is a compatibility fallback. | stdin |

The legacy aliases UNITY_ZEROTIER_NETWORK_ID and
UNITY_ZEROTIER_NETWORK_NAME remain supported. Environment variables override
the corresponding configuration-file values.

The following environment variables are useful for source checkouts, package
installations, and controlled tests:

| Variable | Purpose |
| --- | --- |
| UNITY_LICENSING_MODE_CONFIG_FILE | Use a configuration file at another path. |
| UNITY_LICENSING_MODE_STATE_DIR | Store backups, templates, locks, and transaction metadata elsewhere. |
| UNITY_LICENSING_MODE_LOCK_DIR | Override the operation-lock directory. |
| UNITY_LICENSING_MODE_USER_CONFIG_DIR | Override the Unity user configuration directory. |
| UNITY_LICENSING_MODE_SYSTEM_CONFIG_DIR | Override the Unity system configuration directory. |
| UNITY_LICENSING_MODE_LICENSE_DIR | Override the Unity license directory. |

Source checkouts default to config/local.conf and runtime/. When the
executable is installed outside a Git checkout, defaults do not write into the
installation directory:

- macOS uses ~/Library/Application Support/unity-licensing-mode/.
- Linux uses XDG_CONFIG_HOME or ~/.config/unity-licensing-mode/ for config and
  XDG_STATE_HOME or ~/.local/state/unity-licensing-mode/ for state.

## Commands

| Command | Behavior |
| --- | --- |
| status | Redacted human-readable state report. |
| status --json | Redacted machine-readable state report. |
| doctor | Read-only preflight for platform paths, permissions, processes, provider state, JSON validation, and server reachability. |
| doctor --json | Machine-readable, redacted preflight report. |
| version / --version | Print the version from VERSION. |
| personal | Back up and disable active floating configuration files. |
| floating | Validate, select, and install a floating configuration. |
| reload-client | Stop the Unity Licensing Client so it reloads the selected mode. |
| return-floating | Read a token from stdin or an interactive prompt and return the lease. |

Add --dry-run to any mode-changing command. A dry run does not create a lock,
write files, stop processes, change network settings, or invoke the license
CLI:

~~~
./bin/unity-licensing-mode --dry-run reload-client
./bin/unity-licensing-mode --dry-run return-floating
~~~

Output is colored when stderr is a terminal. Disable it with --no-color, the
NO_COLOR environment variable, or by redirecting output. When
UNITY_NETWORK_ALLOW_CHANGES is off, status, doctor, and floating highlight that
the ZeroTier network will not be joined or configured and print the exact line
to add or the command to prefix.

For a secure floating-lease return:

~~~
printf '%s\n' 'token-from-a-secure-secret-store' \
  | ./bin/unity-licensing-mode return-floating
~~~

With no stdin data, the command prompts without echoing the token. The
positional form return-floating TOKEN remains a deprecated compatibility path
and can expose the token to shell history or process inspection. In stdin
mode, the configured Unity license CLI must read the token from stdin. Set
UNITY_LICENSE_CLI_MODE=argument only when the CLI requires its historical
argument form.

## Safety model

Mode-changing commands use an atomic directory lock under the state directory.
Each operation records metadata under:

~~~
<state-directory>/transactions/<timestamp>-<pid>-<random>-<command>/
~~~

The metadata contains the version, command, timestamps, configuration-file
path, and final status. Before changing Unity configuration, the command
captures the active and managed files it can affect. If a later step fails, it
restores those snapshots and records rolled_back; an incomplete rollback is
recorded as rollback_failed for inspection.

Repeating a successful mode change is safe: existing files are backed up
without deletion, the selected configuration is reinstalled, and the lock is
released on exit.

Floating template selection is strict. The command requires jq, parses each
candidate as JSON, and accepts only an object whose
licensingServiceBaseUrl exactly matches UNITY_LICENSE_SERVER_URL. A malformed,
personal, or wrong-endpoint file is not selected.

ZeroTier route changes are opt-in through
UNITY_NETWORK_ALLOW_CHANGES=true. With that set, floating joins the configured
network (sudo zerotier-cli join) when the node is not already a member and
enables its managed routes. It waits up to ten seconds for the membership to
register and warns if the network status is not yet OK. Authorization on the
network controller is never performed automatically; a joined-but-unauthorized
node still needs to be approved there. With the flag left at false the command
neither joins nor changes any network.

## How switching works

### Personal mode

personal:

1. Optionally preserves a validated floating template.
2. Closes Unity Hub and the Unity Editor.
3. Stops the Unity Licensing Client.
4. Moves active user- and system-level services-config.json files into
   timestamped managed backups.
5. Leaves the local personal-license path available.

The command does not sign in to Unity. After it completes, sign in with the
Unity account you are authorized to use and open Unity normally.

### Floating mode

floating:

1. Validates the provider, server URL, and required provider settings.
2. Requires and validates jq.
3. Selects or preserves a matching floating template.
4. Verifies the existing network-provider state and any explicitly allowed
   route change.
5. Closes Unity Hub and the Unity Editor.
6. Stops the Unity Licensing Client.
7. Backs up active user and system configuration files.
8. Installs the validated template at the system Unity configuration path.
9. Validates the installed JSON and endpoint again.

The command never constructs a services-config.json from only a server URL.
Unity must already have produced a floating configuration, or one must exist
in a managed backup.

## Diagnostics and troubleshooting

Start with:

~~~
./bin/unity-licensing-mode status
./bin/unity-licensing-mode doctor
~~~

Normal status and doctor output does not print licensing-server URLs, network
IDs, network names, lease tokens, or JSON contents. Review file paths before
sharing diagnostics.

For a floating setup:

- doctor should report a valid floating template, the expected provider state,
  and reachable server when those values are configured.
- With ZeroTier, the machine must already be joined and authorized. If managed
  routes are disabled, opt in explicitly or enable the route through the
  authorized network administration workflow.
- A reachable HTTP endpoint proves server reachability only; it does not prove
  that Unity acquired a floating lease.
- If the template is rejected, configure Unity for floating licensing once and
  retry. The helper restores an existing template; it does not invent one.
- If jq is missing, install it before running floating.

If Unity Hub, the Editor, or the Licensing Client does not exit within the
configured timeout, close it manually and retry. The timeout can be adjusted
with UNITY_LICENSING_MODE_TIMEOUT_SECONDS.

## Security and privacy

Keep these files and values private:

- config/local.conf
- runtime/ and installed state directories
- Unity license XML files
- Unity licensing logs
- private licensing-server URLs
- private network identifiers
- floating-license return tokens

The local configuration and runtime state are ignored by Git. Review
git status --ignored before publishing changes or sharing diagnostics.

This project is independent of Unity Technologies. Unity, Unity Hub, Unity
Editor, and related names are trademarks of their respective owners. Use this
tool only with licenses, accounts, networks, and servers you are authorized to
use.

## Repository layout

~~~
bin/unity-licensing-mode       # Executable command
config/example.conf            # Public configuration template
tests/test-command.sh          # Syntax and command-dispatch checks
tests/test-fixtures.sh         # Isolated safety and rollback fixtures
tests/test-release.sh          # VERSION/CLI/changelog consistency checks
VERSION                        # Single version source of truth
CHANGELOG.md                   # Release history
CONTRIBUTING.md                # Contribution workflow
SECURITY.md                    # Security policy
SUPPORT.md                     # Redacted support guidance

config/local.conf              # Local only; ignored by Git
runtime/                       # Local backups and state; ignored by Git
~~~

## Development and releases

Run the local checks from the repository root:

~~~
bash -n bin/unity-licensing-mode
bash tests/test-command.sh
bash tests/test-fixtures.sh
bash tests/test-release.sh
git diff --check
~~~

If installed, run shellcheck bin/unity-licensing-mode tests/*.sh. CI runs the
fixture suite and ShellCheck on Ubuntu, macOS, and Windows runners without
Unity, ZeroTier, sudo, private URLs, credentials, license files, or a live
licensing server.

The maintained line starts at 0.1.0. Release tags use immutable
vMAJOR.MINOR.PATCH names, and the tag, VERSION, package metadata, and CLI
output must match. Breaking changes are documented before 1.0.0.

When opening an issue or pull request, include redacted command output and
clearly distinguish automated, manual, and unavailable validation. Never attach
config/local.conf, runtime/, license files, unredacted logs, server URLs,
network identifiers, or lease tokens.

## License and support

This project is released under the MIT License.

For bugs or improvements, use the issue forms and include a minimal, redacted
reproduction. For licensing, account, server, or entitlement problems, contact
the administrator of the relevant Unity or network service.
