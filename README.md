# Command Center

Command Center is a searchable Linux diagnostics and administration dashboard for Omarchy. It helps you inspect, troubleshoot, and understand your system without memorizing terminal commands. **Expose Linux, don't hide it.** Results identify their Linux sources where useful.

v0.1.0 is a usable first release focused on observation and read-only inspection. It does not offer remediation or system administration actions that change state.

## Features

- **Dashboard:** CPU usage, memory usage, root storage usage, uptime, failed service count, and local network state.
- **System tools:** System Overview, Disk Usage, Memory Usage, and Failed Services.
- **Network tools:** Network Overview, Listening Ports, Ping Host, and DNS Lookup.
- **Diagnostics:** System Health and Network Diagnostic, with individual checks and their observed results.
- **Search:** Find tools by name or keyword and navigate with the keyboard.

## Requirements

Command Center targets Omarchy 4 / Quattro with the Quickshell-based Omarchy shell. It uses Linux virtual files and standard system utilities, including `cat`, `ip`, `ss`, `systemctl`, `resolvectl`, `findmnt`, and `ping`. Availability of individual results depends on those utilities and the permissions of the shell process. Other distributions and environments have not been tested.

Node.js is used for development tests; it is not required to run the plugin.

## Install

Install from GitHub with Omarchy's plugin command:

```bash
omarchy plugin add https://github.com/Hightech89/omarchy-command-center.git
```

Enable the menu plugin if it is not already enabled, then summon it:

```bash
omarchy plugin enable io.github.hightech89.command-center
omarchy-shell shell summon io.github.hightech89.command-center '{}'
```

To remove an installed copy:

```bash
omarchy plugin remove io.github.hightech89.command-center
```

## Optional keybind

Command Center does not claim a default keybind. You may add one in `~/.config/hypr/bindings.lua` if you want quick access. First check `omarchy menu keybindings --print` and choose an unused combination. The following `SUPER + SHIFT + C` binding is an **example only**; change it if that key is already assigned:

```lua
o.bind("SUPER + SHIFT + C", "Command Center", "omarchy-shell shell toggle io.github.hightech89.command-center '{}'")
```

No Hyprland configuration is changed during installation.

## Security model

Command Center runs predefined commands with bounded arguments. It does not expose arbitrary shell execution or interpolate user input into `bash -c` or `sh -c`; Ping Host and DNS Lookup validate input before passing it to fixed programs. The v0.1.0 diagnostics are observational and read-only. There are no `sudo` or `pkexec` actions, package installation or removal, service start/stop/restart controls, or firewall or configuration mutation.

Network Diagnostic may send user-initiated ICMP echo requests to fixed public diagnostic endpoints. Command Center does not send telemetry.

## Local Development

For development, work from a checkout in `~/.config/omarchy/plugins/command-center`, then run:

```bash
omarchy plugin validate .
node --test tests/*.test.cjs
qs --no-color -p ProcessRunnerSmoke.qml
qs --no-color -p SystemServiceSmoke.qml
qs --no-color -p NetworkServiceSmoke.qml
qs --no-color -p DiagnosticsServiceSmoke.qml
omarchy-shell shell summon io.github.hightech89.command-center '{}'
```

If the shell has not picked up a local edit, run `omarchy-shell shell rescanPlugins`.

## License

MIT. See [LICENSE](LICENSE).
