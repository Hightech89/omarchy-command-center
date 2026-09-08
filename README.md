# Command Center

Command Center is an early-development community menu plugin for Omarchy 4 / Quattro.

Current functionality is intentionally minimal: the plugin can be discovered, enabled, and summoned as a simple Omarchy menu that displays "Command Center".

Planned direction: a searchable, keyboard-first dashboard for read-only System and Network inspection, deterministic diagnostics, and Linux learning. See [SPEC.md](SPEC.md) for the v0.1 product specification and acceptance criteria.

Arbitrary shell command execution is not a project goal. Actions will be predefined, and user inputs will be validated before they are used.

## Local Development

Clone or place this directory at:

```bash
~/.config/omarchy/plugins/command-center
```

Validate the plugin:

```bash
omarchy plugin validate ~/.config/omarchy/plugins/command-center
```

Rescan plugins if needed:

```bash
omarchy-shell shell rescanPlugins
```

Enable and summon it:

```bash
omarchy plugin enable community.command-center
omarchy-shell shell summon community.command-center '{}'
```

## License

MIT
