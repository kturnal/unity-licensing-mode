# unity-licensing-mode

Small macOS command-line helper for switching Unity between:

- personal licensing, using the local Unity account/license path; and
- floating licensing, using a Unity licensing server reachable through ZeroTier.

The command closes Unity cleanly, stops the Unity licensing client, preserves configuration backups, and restores the selected licensing configuration. It does not bypass Unity licensing or provide a licensing server.

## Requirements

- macOS
- Unity Hub and the Unity Editor
- ZeroTier with access to the licensing network
- the Unity floating licensing server
- jq for endpoint verification when available
- the local unity-license CLI if returning a floating lease

## Setup

From the repository directory:

    cp config/example.conf config/local.conf
    chmod 600 config/local.conf

Edit config/local.conf with the private ZeroTier network ID/name, licensing-server URL, and local Unity CLI path. Never commit that file.

The command keeps runtime backups in runtime/. That directory is also ignored and must never be uploaded.

## Usage

    ./bin/unity-licensing-mode status
    ./bin/unity-licensing-mode personal
    ./bin/unity-licensing-mode floating
    ./bin/unity-licensing-mode reload-client
    ./bin/unity-licensing-mode return-floating TOKEN

If the command directory is on your PATH, the installed entry points can be used as:

    unity-licensing-mode status
    ulm floating

Commands that update /Library/Application Support/Unity request sudo. Save and close Unity before changing modes.

## Safety and privacy

Do not commit:

- config/local.conf
- runtime/
- Unity license XML files
- Unity licensing logs
- private server addresses or network identifiers

Review the script before running it on another machine. The tool changes local Unity configuration and may affect all Unity projects on that Mac.

## License

MIT. See LICENSE.
