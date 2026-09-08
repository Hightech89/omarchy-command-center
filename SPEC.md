# Omarchy Command Center — Product Specification

Status: v0.1 source of truth  
Product: `community.command-center`  
Version: 0.1

## 1. Product definition

Omarchy Command Center is a searchable Linux diagnostics and administration dashboard for Omarchy. It helps users inspect, troubleshoot, and understand their system without memorizing terminal commands.

Core philosophy: **Expose Linux, don't hide it.**

Command Center complements Omarchy's native Super+Space menu. The native menu remains responsible for Omarchy configuration and launching actions. Command Center focuses on system inspection, network inspection, deterministic diagnostics, troubleshooting, and Linux learning.

## 2. v0.1 goals and principles

v0.1 is primarily read-only. It observes and diagnoses the system rather than modifying it.

The product should:

- present structured, readable information instead of raw terminal output;
- make keyboard use first-class;
- show the underlying Linux tool or command where appropriate, so users learn what powers each result;
- use Omarchy/Quickshell native theme tokens and patterns, inheriting the active user theme;
- keep UI, command definitions, execution, and structured result presentation separated where practical;
- avoid over-engineering and follow patterns used by installed Omarchy Quattro plugins.

## 3. v0.1 scope

### Dashboard

The dashboard provides at-a-glance values for CPU usage, memory usage, root/storage usage, uptime, basic network state, and failed-service count.

### System

1. **System Overview** — hostname, OS information, kernel, uptime, CPU, RAM, storage, and load.
2. **Disk Usage** — mounted filesystems with usage and capacity. Recursive filesystem scanning is out of scope.
3. **Memory Usage** — total, used, available, and swap when applicable.
4. **Failed Services** — failed systemd units for inspection only. Starting, stopping, or restarting units is out of scope.

### Network

5. **Network Overview** — active interface, local IP, default gateway, DNS information, and basic connection state.
6. **Listening Ports** — TCP/UDP listening sockets and associated process where available, presented readably.
7. **Ping Host** — a user-provided hostname or IP with strict validation and clean latency/packet-loss results.
8. **DNS Lookup** — a user-provided domain/hostname with strict validation and clearly presented resolved addresses.

### Diagnostics

9. **System Health** — deterministic, lightweight checks for CPU/load, memory pressure, storage utilization, failed services, and basic system status.
10. **Network Diagnostic** — a predefined sequence checking interface state, IP address, default gateway, gateway reachability, DNS resolution, and internet reachability. Each check is shown individually with an indication of approximately where a failure occurred.

Diagnostics must state what was checked and must not claim AI diagnosis or certainty beyond the checks performed.

## 4. Search and keyboard UX

v0.1 supports searching tools/actions. Command metadata is structured and conceptually includes:

- stable ID;
- display name;
- description;
- category;
- keywords;
- risk level;
- whether user input is required.

Metadata must reference predefined actions; it must not contain arbitrary executable shell strings.

Keyboard behavior is first-class:

- typing searches;
- Up/Down navigates results;
- Enter selects or runs the selected action;
- Escape goes back or closes the interface.

No global Omarchy keybinding is assigned or modified in v0.1.

## 5. Linux learning

Where appropriate, results identify the underlying Linux tool or command responsible for the information. Examples include `ss -tulpn` for listening ports and `systemctl --failed` for failed services. v0.1 does not require extensive flag-by-flag command education.

## 6. Security and safety boundaries

All actions are predefined and use structured execution. For Ping Host and DNS Lookup, input is strictly validated and passed as an argument to a fixed executable where supported. Raw user input must never be turned into a shell command.

The following are prohibited in v0.1:

- arbitrary command execution or arbitrary shell text boxes;
- `eval`, `bash -c` with user-generated strings, or unsafe input interpolation;
- automatic sudo;
- package installation or removal;
- file deletion;
- process termination;
- service start/stop/restart;
- firewall modification;
- configuration-file modification.

## 7. Architecture expectations

Keep these concerns separated where practical:

```text
UI → command metadata/definition → execution/service layer → structured result/presentation
```

`Menu.qml` must not become a single file containing the entire UI, command catalog, execution logic, and shell strings. The exact file structure is intentionally left open.

## 8. Explicit non-goals

The following are out of scope for v0.1: Omarchy theme management, Omarchy plugin management, package management, Git tools, Docker tools, process management, service modification, log-management workflows beyond what is strictly needed for defined v0.1 features, a security dashboard, firewall management, SSH activity analysis, and failed-login analysis.

## 9. v0.1 acceptance criteria

Release review must be able to verify all of the following:

1. The plugin validates successfully with `omarchy plugin validate .`.
2. The dashboard displays CPU, memory, root/storage, uptime, basic network state, and failed-service count, with an understandable loading, unavailable, or error state when a value cannot be obtained.
3. System Overview displays hostname, OS, kernel, uptime, CPU, RAM, storage, and load from structured results.
4. Disk Usage lists mounted filesystems with usage/capacity and performs no recursive filesystem scan.
5. Memory Usage displays total, used, available, and swap when the platform exposes swap.
6. Failed Services lists failed systemd units for inspection and exposes no start, stop, or restart control.
7. Network Overview displays the active interface, local IP, default gateway, DNS information, and basic connection state, including clear unavailable states where applicable.
8. Listening Ports displays TCP and UDP listeners and associated processes when available without requiring users to interpret raw terminal output.
9. Ping Host rejects invalid input before execution and presents latency and packet-loss results without shell interpolation.
10. DNS Lookup rejects invalid input before execution and presents resolved addresses without shell interpolation.
11. System Health runs only the defined lightweight checks, applies documented deterministic thresholds, and labels results with the check performed and its evidence.
12. Network Diagnostic shows each predefined check independently and identifies the approximate failing stage when a check fails.
13. Search can find each v0.1 action by display name and relevant keywords; metadata includes stable ID, description, category, risk level, and input requirement.
14. Typing, Up/Down, Enter, and Escape perform the defined keyboard behaviors, and no global Omarchy keybinding is changed.
15. The UI uses native Omarchy/Quickshell theme tokens and adapts to the active theme; it does not introduce hard-coded personal Cyberdeck colors.
16. A code review confirms there is no arbitrary command execution, user-generated shell string, automatic sudo, package/file/process/service/firewall/configuration mutation, or out-of-scope workflow.
17. Appropriate failure, timeout, permission, and unavailable-data states are readable and do not present fabricated values or claims of certainty beyond the executed check.

## 10. Roadmap

- **v0.1 — Observe:** system/network visibility, lightweight diagnostics, search, keyboard navigation, and educational command information.
- **v0.2 — Diagnose:** deeper network troubleshooting, disk-space investigation, service/log inspection, boot diagnostics, and performance troubleshooting.
- **v0.3 — Administer:** carefully controlled state-changing service, process, and maintenance actions with appropriate confirmations and privilege handling.
- **v0.4 — Security:** firewall visibility, SSH/authentication activity, security posture information, and optional security-tool integrations.

## 11. Open implementation decisions

The following must be resolved during implementation and documented alongside the relevant feature:

- exact data sources and portable parsing strategy for OS, network, DNS, and process information;
- the numeric thresholds for CPU/load, memory pressure, storage utilization, failed services, and basic system status;
- the definition of “internet reachability” and the controlled endpoint or endpoints used by the network diagnostic;
- the accepted hostname/IP/domain grammar, including IPv6 and IDN handling;
- behavior when commands are unavailable, denied, time out, or return partial data;
- the Quickshell/Omarchy-native patterns to use after inspecting installed Quattro plugins.

These decisions must preserve the read-only, deterministic, structured, and safe boundaries above.
