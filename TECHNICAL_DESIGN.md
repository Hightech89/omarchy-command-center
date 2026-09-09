# Omarchy Command Center v0.1 — Technical Design

Status: proposed implementation design  
Product source of truth: `SPEC.md`  
Researched environment: Omarchy 4.0.3, Quickshell 0.3.1, systemd 261,
iproute2 7.2.0, util-linux 2.42.3, GNU coreutils 9.11, iputils 20250605

## 1. Scope and design principles

This document resolves the open implementation decisions in `SPEC.md`. It is
not an implementation plan for later roadmap features. Command Center v0.1 is
an unprivileged, read-only observer. It must never install software, invoke
sudo or polkit, alter configuration, manage services, kill unrelated
processes, or expose arbitrary command execution.

The design follows these rules:

1. Execute only code-owned action IDs mapped to fixed executable paths and
   separate argument arrays.
2. Keep every potentially blocking operation outside the QML UI event path by
   using Quickshell's asynchronous `Process` type.
3. Prefer kernel virtual files and machine-readable output from tools already
   present in Omarchy.
4. Parse into typed, bounded result objects before presentation. UI components
   never interpret stdout.
5. Make uncertainty visible. `unavailable`, `error`, and legitimate `empty`
   are different states, and a failed probe is not stronger evidence than the
   probe actually supplies.
6. Cancel work that no longer has a visible consumer, and reject stale results.
7. Use Omarchy's shared `Color`, `Style`, `Border`, and UI components rather
   than a plugin-specific palette.

No new package dependency is required by this design.

## 2. Researched local patterns

The following installed sources informed the design. All paths under
`/usr/share/omarchy` are references only and must remain unmodified.

| Concern | Local reference | Relevant pattern |
|---|---|---|
| Native process API | `/usr/lib/qt6/qml/Quickshell/Io/quickshell-io.qmltypes:48-190` | `Process.command` is a `QStringList`; `started`, `exited(exitCode, exitStatus)`, `processId`, `signal()`, stdout, and stderr are available. |
| Whole-output and line parsers | `/usr/lib/qt6/qml/Quickshell/Io/quickshell-io.qmltypes:282-339` | `SplitParser` emits records; `StdioCollector` exposes text/data and `streamFinished`, with optional `waitForEnd`. |
| Safe argv and replacement | `/usr/share/omarchy/shell/plugins/panels/wifiqr/Panel.qml:96-188` | Builds argv arrays, stops an in-flight process, queues the newest request, ignores canceled output, and notes that exit/stream callback order is not guaranteed. |
| Close-time cleanup | `/usr/share/omarchy/shell/plugins/panels/speedtest/Panel.qml:50-68` and `/usr/share/omarchy/shell/plugins/panels/disk-speedtest/Panel.qml:32-52` | Closing a panel stops timers and active work through the plugin lifecycle. |
| Timeout and stale-result guard | `/usr/share/omarchy/shell/Ui/MultiSelect.qml:178-251` | Uses a monotonic request sequence, a `Timer`, async `Process`, stdout collection, and explicit timeout/error state. |
| Strict structured parsing | `/usr/share/omarchy/shell/Ui/MultiSelect.qml:153-176` | Malformed output that claims to be JSON becomes an error rather than silently falling back to text. |
| Streaming parse | `/usr/share/omarchy/shell/plugins/panels/speedtest/Panel.qml:76-160` | Parses bounded line records while a process runs and maintains explicit running/error/phase state. |
| Pure parser/model separation | `/usr/share/omarchy/shell/plugins/panels/monitor/Model.js:94-112` and `/usr/share/omarchy/shell/plugins/panels/network/Model.js` | Keeps normalization and parsing in plain JavaScript helpers rather than delegates. |
| Search ranking | `/usr/share/omarchy/shell/plugins/menu/MenuModel.js:279-351` | Normalizes searchable tokens, AND-matches terms, and deterministically ranks exact/prefix/name/description matches. |
| Search list and empty state | `/usr/share/omarchy/shell/plugins/menu/Menu.qml:561-639` and `:1392-1417` | Rebuilds a structured `ListModel`, clamps selection, reveals the cursor, and distinguishes “No matches” from an empty menu. |
| Keyboard navigation | `/usr/share/omarchy/shell/plugins/menu/Menu.qml:642-745` and `:1068-1117` | One cursor model serves keyboard and pointer; Up/Down wrap, Enter activates, Escape clears search then closes, and the list follows selection. |
| Reusable panel keys | `/usr/share/omarchy/shell/Ui/PanelKeyCatcher.qml:23-84` | `Keys.BeforeItem` dispatches semantic navigation while allowing an active editor to block the catcher. |
| Focus after mapping | `/usr/share/omarchy/shell/plugins/menu/Menu.qml:795-838` and `/usr/share/omarchy/shell/plugins/panels/wifiqr/Panel.qml:51-67` | Calls `forceActiveFocus()` via `Qt.callLater()` after a hidden surface becomes visible. |
| Loading/error/empty UI | `/usr/share/omarchy/shell/Ui/MultiSelect.qml:430-499` | Disables refresh during work, displays a spinner, and gives loading, error, and empty states distinct copy. |
| Plugin lifecycle | `/usr/share/omarchy/shell/Ui/Panel.qml:21-57` and `/usr/share/omarchy/shell/README.md` | Uses host-mediated open/close/hide lifecycle and injected plugin capabilities. |
| Theme palette | `/usr/share/omarchy/shell/Commons/Color.qml:7-32` and `:73-102` | Foundational and menu surface roles come from active `colors.toml`/`shell.toml`. |
| Structural tokens | `/usr/share/omarchy/shell/Commons/Style.qml:6-27`, `:34-93`, and `:201-260` | Typography, spacing, radii, border, hover, focus, and selection are theme-scaled shared tokens. |
| Existing plugin shell | `Menu.qml:27-68` | Already uses `Color.menu.*`, `Style.*`, an overlay layer, exclusive keyboard focus, and host hide behavior; it should become composition only. |

Some first-party code uses `bash -c` for trusted packaged scripts. That is not
the pattern selected here. Command Center handles user input and has a stricter
boundary from `SPEC.md`, so all v0.1 probes use direct executables and argv.

The locally installed `Quickshell.Networking` singleton exposes NetworkManager
device/connectivity objects, and the first-party network panel uses it at
`/usr/share/omarchy/shell/plugins/panels/network/Panel.qml:68-73`. Command
Center should not use mutating members such as `wifiEnabled` or `disconnect()`.
For diagnostic evidence, iproute2 JSON remains preferable: it represents the
kernel routing and address state directly, works independently of a particular
network manager, and is easier to snapshot into immutable result data.

## 3. Proposed architecture

### 3.1 Dependency direction

```text
Menu.qml / views
        ↓ action ID, validated input, refresh/cancel intent
CommandCatalog.js + controller
        ↓ fixed request definition
SystemService.qml / NetworkService.qml / DiagnosticsService.qml
        ↓ ProcessRunner request (absolute executable + argv)
ProcessRunner.qml
        ↓ bounded execution record
SystemParsers.js / NetworkParsers.js
        ↓ structured result
view-model formatting helpers
        ↓ display-only props
reusable UI components
```

The execution direction is one-way. UI code cannot submit an executable or
argv. It submits a stable action ID and, only for the two input actions, a
validated value. The controller owns the switch from action ID to service
method. `CommandCatalog.js` is discoverability metadata, not executable data.

### 3.2 Recommended project structure

```text
Menu.qml                         # plugin lifecycle and top-level composition
catalog/
  CommandCatalog.js             # stable ID/name/description/category/keywords/risk/input
controllers/
  CommandCenterController.qml   # route, selection, refresh, back, cancellation
services/
  ProcessRunner.qml             # async lifecycle, timeout, output bounds, result envelope
  SystemService.qml             # system snapshots and health inputs
  NetworkService.qml            # network snapshots, ping, DNS, sockets
  DiagnosticsService.qml        # deterministic orchestration only
parsers/
  SystemParsers.js              # /proc, os-release, systemd, findmnt
  NetworkParsers.js             # ip/resolvectl/ss/ping
  Validation.js                 # host/IP grammar
  Result.js                     # constructors and status constants
presentation/
  Formatters.js                 # bytes, duration, percentages, command labels
ui/
  SearchView.qml
  DashboardView.qml
  ResultView.qml
  DiagnosticView.qml
  StatusCard.qml
  StateMessage.qml
```

This is intentionally a shallow structure. Do not add a general command
framework, dependency injection container, persistent database, background
daemon, or separate helper program for v0.1. If implementation experience
shows that the three service files are small, combining them into two is fine;
the dependency direction and parser boundary matter more than exact filenames.

### 3.3 Command catalog

Each catalog record contains only:

```text
id, name, description, category, keywords[], risk, inputKind, resultView,
learningLabel
```

`risk` is `read-only` for every v0.1 action. `inputKind` is `none`, `host`, or
`dns-name`. `learningLabel` is static educational text such as
`ss -H -lntu -p`; it is never executed. Executable paths, options, timeouts,
and parsers live in services, outside metadata.

## 4. Process execution model

### 4.1 Native mechanism

Use `Quickshell.Io.Process` with an argv list:

```text
command = ["/usr/bin/ping", "-n", "-c", "4", "-W", "1", "-w", "5", "--", validatedHost]
```

The first item is always a code-owned absolute path; remaining items are
separate arguments. Never join the list into a string. Never use `eval`, a
shell, command substitution, redirection, or `bash -c`. User input may occupy
one final argument only after validation. A leading-option injection is also
blocked by the grammar and, where supported, the `--` terminator.

Absolute `/usr/bin/...` paths avoid PATH shadowing and make an unavailable
tool deterministic. Keep the inherited desktop environment because user
systemd/DBus queries may require `XDG_RUNTIME_DIR` and session bus variables,
but override parsing-sensitive values:

- `LC_ALL=C` and `LANG=C` for text-only tools (`ss`, `ping`, `/proc` helpers);
- `SYSTEMD_COLORS=0`, `SYSTEMD_PAGER=cat`, and explicit `--no-pager` for
  systemd tools;
- no environment value is constructed from user input.

Machine-readable JSON is preferred over locale control when both exist.

### 4.2 Execution record and state machine

Every request receives a monotonically increasing `runId` and produces this
internal record:

```text
runId, actionId, state, startedAt, finishedAt, timedOut, canceled,
exitCode, exitStatus, stdoutState, stderrState, stdout, stderr
```

`state` progresses through `queued → running → settling → complete`; terminal
alternatives are `canceled`, `timeout`, `unavailable`, and `error`.

Use `StdioCollector { waitForEnd: true }` only for known-small bounded output
such as JSON snapshots. Use `SplitParser` for `ss`, ping progress if shown, and
other row streams. Because local first-party comments establish that
`onExited` and `onStreamFinished` have no guaranteed order, the runner records
all three independently: process exit, stdout completion, and stderr
completion. It finalizes only when required events have arrived, or after a
short post-exit drain deadline. A nonzero exit cannot be overwritten by a late
successful parse, and late stderr cannot overwrite a newer request.

The runner must enforce conservative bounds before data enters result models:

- small snapshot stdout: 1 MiB maximum;
- stderr retained for classification/debug detail: 32 KiB maximum;
- row streams: 10,000 rows or 2 MiB accepted text, whichever comes first;
- any individual displayed field: 4 KiB maximum;
- diagnostic messages shown to users: normalized and truncated to 512 chars.

Crossing a bound terminates that request and returns `error` with
`reason: output-limit`. It must not render a partial list as complete.

### 4.3 Exit, failure, and command availability

- Exit code 0 plus a valid parse yields `success` or legitimate `empty`.
- A signaled/crashed process (`exitStatus` not normal) yields `error` unless
  Command Center initiated cancellation/timeout.
- A normal nonzero exit is classified by the specific service. Expected
  negative outcomes (ping no replies, DNS name not found) become structured
  completed results, not generic application errors.
- Failure to emit `started`, immediate fall-back to `running: false`, or a
  failed launch of the fixed absolute path yields `unavailable` with the tool
  name. The normal timeout remains a backstop if the local Process API does not
  expose a distinct launch error callback to QML.
- Permission-denied stderr/exit becomes `unavailable` for optional fields (for
  example socket owner), or `error: permission-denied` when it prevents the
  whole requested result. Command Center never retries with privilege.

Raw stderr is not displayed verbatim by default. Services map known failure
classes to concise messages and may include a bounded, plain-text detail line.

### 4.4 Timeout policy

| Operation | Deadline |
|---|---:|
| `/proc`, `/sys`, os-release, iproute2, `findmnt`, `ss`, hostname | 2 s |
| systemd manager query | 3 s per system/user query |
| DNS lookup | 5 s |
| Ping Host | 6 s (`ping` also receives `-w 5`) |
| Gateway ping | 4 s |
| Each public reachability target | 3 s, with an 8 s total stage budget |
| Whole Network Diagnostic | 20 s hard ceiling |

The QML timer is authoritative even when the executable has its own deadline.
On timeout, mark the generation stale, request SIGTERM by setting
`Process.running = false`, wait 500 ms, then call `Process.signal(9)` if the
same PID/generation is still running. Stop and clear both timers after exit.
The UI immediately shows `timeout`; late output is discarded.

### 4.5 Cancellation and cleanup

- **Command Center closes:** cancel every interactive action and diagnostic,
  stop refresh/debounce/timeout timers, clear pending replacement requests,
  and invalidate all run IDs. Low-cost dashboard snapshots should also stop;
  they refresh on the next open.
- **An action is replaced:** latest request wins. Invalidate the old run, send
  termination, and queue the replacement until the old process has exited and
  its streams have settled. Never mutate a running `Process.command` and assume
  it changed the active process.
- **A process hangs:** apply the timeout and TERM/KILL sequence above.
- **A process exits unsuccessfully:** finalize its structured failure, leave
  the interface responsive, and offer a normal retry. Do not automatically
  loop network/system failures.
- **Plugin object destruction or hot reload:** `Component.onDestruction`
  invalidates runs and initiates the same termination path as close.

The chosen fixed utilities do not intentionally daemonize or start persistent
children. Quickshell `Process` has no documented process-group control in the
installed QML API, so v0.1 must not add a command that backgrounds descendants.
If that constraint changes, process-group containment requires a separately
reviewed design rather than a shell wrapper.

### 4.6 Responsiveness and concurrency

Never use synchronous JavaScript loops over unbounded output or synchronous
process APIs on the UI thread. Parsing is lightweight, bounded, and performed
when async data arrives. Read the small `/proc`, `/sys`, and `/etc` sources
through the same asynchronous runner using fixed `/usr/bin/cat` argv; do not
perform synchronous file reads from a UI event handler. Dashboard requests may
run concurrently, but cap the plugin at four active child processes.
Interactive actions take priority; queue lower-priority dashboard refreshes
rather than spawning without limit. Debounce search/input validation locally
(no process needed), and do not poll faster than the values warrant.

Suggested refresh behavior while the dashboard is visible:

- CPU sample: two `/proc/stat` snapshots 500 ms apart; refresh every 2 s;
- memory/load/network counters: every 5 s;
- storage and failed services: on open and explicit refresh, at most every
  30 s automatically;
- uptime can advance from a monotonic UI timer after an authoritative initial
  snapshot.

## 5. Structured result and parsing model

### 5.1 Public result envelope

Services publish immutable replacement objects, never mutate a QML `var` map
in place:

```text
{
  actionId,
  status,          // loading | success | empty | unavailable | error | timeout | canceled
  data,            // action-specific typed object or null
  message,         // concise user-facing explanation
  reason,          // stable machine key, e.g. command-missing
  evidence[],      // structured labels/values used by diagnostics
  source: { tool, displayCommand },
  observedAt,
  completeness    // complete | partial
}
```

Diagnostic check results add `severity: healthy | warning | critical |
unavailable | error`. Execution status and diagnostic severity are separate:
a successfully executed ping can produce a critical “no replies” diagnostic.

### 5.2 Parser contract

Each parser is a pure JavaScript function taking bounded text and returning
either `{ ok: true, data, completeness, warnings }` or
`{ ok: false, reason, message }`. It must:

1. verify top-level JSON types and required properties;
2. coerce no ambiguous values (for example, `"72%"` is parsed only where that
   exact schema is expected);
3. reject non-finite, negative, or impossible numeric values;
4. normalize strings and cap their length;
5. copy primitives into new objects—never retain live QObjects or raw parser
   buffers in a view model;
6. return a new result object so QML change notification is reliable.

For JSON Lines (notably `resolvectl query`), parse each non-empty line as one
complete JSON object. A malformed line makes the requested lookup malformed;
do not silently omit it and claim a complete answer.

### 5.3 Required edge-case behavior

- **Malformed output:** `error: malformed-output`; retain no fabricated
  values. A prior successful dashboard value may remain visibly labeled
  “stale” with its timestamp, but cannot be represented as current.
- **Partial output:** publish only if the feature defines optional fields and
  all required fields validate. Set `completeness: partial` and list missing
  optional evidence. A timeout, output-limit, truncated JSON, or interrupted
  row is never successful partial output.
- **Unavailable command:** `unavailable: command-missing` naming the fixed
  tool. Do not search arbitrary PATH locations or install it.
- **Permission denied:** optional protected fields become `null` with an
  explanation; a wholly blocked query becomes `error: permission-denied`.
- **Legitimate empty:** `empty`, not `error`. Examples are zero failed units,
  no swap configured, no listening socket owner visible, or no DNS answer of a
  requested family. Copy must explain the empty meaning.

All output-derived QML `Text` uses `textFormat: Text.PlainText`. No command
output becomes rich text, QML, a URL to open automatically, or another command.

## 6. Data-source matrix

Commands below are educational approximations where abbreviated. The service
stores an exact argv definition independently and uses absolute paths.

| Feature/value | Preferred source | Structured command / parse | Fallback and semantics |
|---|---|---|---|
| Dashboard CPU | `/proc/stat` | Parse aggregate `cpu` counters twice; delta usage = `(deltaTotal - deltaIdle) / deltaTotal`, where idle is `idle+iowait` and total excludes duplicate guest fields. | Unavailable if counters are absent/non-monotonic. |
| Dashboard memory | `/proc/meminfo` | `used = MemTotal - MemAvailable`; retain total/available and swap. | Fall back to `MemFree+Buffers+Cached` only if documented as estimated; normally mark unavailable when `MemAvailable` is absent. |
| Dashboard root storage | mounted root filesystem | `findmnt --json --bytes --df --target / --output SOURCE,FSTYPE,SIZE,USED,AVAIL,USE%,TARGET` | `df --block-size=1 --output=source,fstype,size,used,avail,pcent,target /` only if findmnt JSON is unavailable; parse its header-defined fields carefully. |
| Dashboard uptime | `/proc/uptime` | First finite nonnegative seconds field. | `systemctl show -p RuntimeWatchdogUSec` is not equivalent; no fabricated fallback. |
| Dashboard network state | kernel route/link/address | `ip -j route show default`, then `ip -j link show` and `ip -j address show`. | Quickshell `Networking` may supply a display hint only; absence of a default route is a valid disconnected state. |
| Dashboard failed count | systemd | `systemctl --system --failed --no-pager --no-legend --plain --output=json list-units`; also query `--user` and label scope. | If one manager is unavailable, return a partial count with the missing scope identified. |
| System Overview: hostname | `/proc/sys/kernel/hostname` | Trim one line; cap at Linux hostname length. | `hostnamectl --json=short status` is an optional single-query alternative. Ignore sensitive fields such as machine ID, serial, UUID. |
| System Overview: OS | `/etc/os-release` | Parse shell-like `KEY=VALUE` data with a dedicated non-executing parser; use `PRETTY_NAME`, then `NAME` + `VERSION_ID`. Never source the file. | `hostnamectl --json=short status` operating-system fields if available. Strip ANSI controls from display. |
| System Overview: kernel | `/proc/sys/kernel/ostype`, `/proc/sys/kernel/osrelease` | Small file reads. | `/usr/bin/uname -sr`; fixed argv. |
| System Overview: CPU | `/proc/cpuinfo`, `/proc/stat` | Model name from first `model name`; logical CPU count from processor records; usage from sampled stat. | Missing model is unavailable while count/usage may remain available. |
| System Overview: RAM | `/proc/meminfo` | Same canonical memory snapshot as dashboard. | None needed on supported Linux. |
| System Overview: storage | root `findmnt` snapshot | Same canonical root record as dashboard. | Same `df` fallback. |
| System Overview: load | `/proc/loadavg` | Parse 1/5/15-minute finite nonnegative values and running/total tasks. | None needed on supported Linux. |
| Disk Usage | kernel mount table + statfs | `findmnt --json --bytes --df --real --output SOURCE,FSTYPE,SIZE,USED,AVAIL,USE%,TARGET,OPTIONS`. | `df` fallback. No directory walk or recursive scan. Preserve mountpoints containing spaces via JSON. |
| Memory Usage | `/proc/meminfo` | Total, `MemTotal-MemAvailable`, available, and swap total/free/used. | Swap total 0 is legitimate “Not configured,” not unavailable. |
| Failed Services | systemd system and user managers | Same JSON `list-units --state=failed` queries; parse unit/load/active/sub/description and tag scope. | Empty arrays mean healthy/empty. Never expose action controls. |
| Network Overview: interface/gateway | iproute2 | Choose lowest-metric usable default route from `ip -j route show default`; join by `dev` to link JSON. | Multiple equal routes are shown and the chosen primary is labeled. No default route is disconnected, not a parser error. |
| Network Overview: local IP | iproute2 | Prefer route `prefsrc`; otherwise global-unicast addresses on chosen interface, separately IPv4/IPv6. Exclude loopback/link-local from “internet address” but optionally show link-local detail. | No address is a valid stage failure. |
| Network Overview: DNS | systemd-resolved | `resolvectl --json=short status`; select the chosen interface's current server/servers and search domains. | Parse `/etc/resolv.conf` without following its values as commands; a loopback stub is labeled “local stub” rather than claimed as the upstream server. If another resolver owns the system, show the resolv.conf data as partial. |
| Network Overview: basic state | derived evidence | Interface flags/operstate + address + default route; optionally show `Networking.connectivity` as a separate NetworkManager hint. | Never equate carrier alone with internet access. |
| Listening Ports | kernel socket diagnostics | `ss -H -l -n -t -u -p`; parse netid/state/local/peer and bounded `users:(...)` metadata. | Owner/process is nullable because unprivileged users cannot see all owners. Never add sudo. |
| Ping Host | iputils | `ping -n -c 4 -W 1 -w 5 -- <validated>` under C locale. Parse transmitted/received/loss and min/avg/max/mdev summary. | No replies is a valid unsuccessful network result. IPv4/IPv6 literals may add fixed `-4`/`-6`; names use normal family selection. |
| DNS Lookup | systemd-resolved | Run `resolvectl --json=short query --type=A <validated>` and a separate `--type=AAAA` request; parse JSON Lines and deduplicate addresses. | A/AAAA emptiness is valid; overall not-found is a structured negative result. If resolved is unavailable, `/usr/bin/getent ahosts <validated>` is a partial, text-parsed fallback and must be labeled as NSS rather than a DNS-record query. |
| System Health | canonical snapshots above | No extra broad command; reuse fresh CPU, load, memory, mount, failed-unit, and system-manager records. | Each missing source yields an unavailable/error check, not an invented value. |
| Network Diagnostic | iproute2, iputils, systemd-resolved | Staged design in section 9. | No telemetry or background connectivity polling. |

`findmnt --real` is the correct baseline for Disk Usage because the local JSON
probe showed pseudo mounts and repeated Btrfs subvolume views when `--real`
was omitted. Display each real mountpoint, but for health scoring deduplicate
identical capacity records from the same backing filesystem so Btrfs
subvolumes do not multiply one warning.

## 7. Input validation and safe argument flow

### 7.1 General pipeline

```text
typed text → exact grammar validator → normalized typed value
           → service method → fixed argv slot → Quickshell Process
```

Validation is local and complete before a process starts. Reject leading or
trailing whitespace instead of silently changing the target. Maximum input is
253 ASCII characters for a DNS name without its optional trailing root dot
(254 with it), and 45 characters for an IPv6 literal. Never accept control
characters, whitespace, URL syntax, credentials, ports, paths, brackets, `%`
zone IDs, wildcard characters, or a leading `-`.

The validator returns a discriminated object such as `{ kind: ipv4|ipv6|name,
value }`, not a boolean. The service accepts only that object, rechecks its
shape, and appends `value` as one argv item. Presentation retains the original
safe display value separately from the normalized execution value.

### 7.2 IPv4 grammar

Accept exactly four ASCII decimal octets separated by dots:

```text
dec-octet "." dec-octet "." dec-octet "." dec-octet
```

Each octet is 0–255. Reject signs, hex/octal shorthand, fewer than four
components, empty components, and leading zeroes except the single digit `0`.
If input is dotted-numeric-looking but fails this grammar, do not retry it as a
hostname.

### 7.3 IPv6 grammar

Implement an algorithmic parser rather than one giant regex:

- ASCII hex digits only, case-insensitive;
- each `h16` has 1–4 digits;
- at most one `::`, which compresses at least one 16-bit group;
- exactly eight groups without `::`, fewer than eight with it;
- one optional final embedded strict IPv4 address counts as two groups;
- reject brackets, port suffixes, `%zone`, multiple `::`, empty groups outside
  the compression marker, and more than 128 bits.

Normalize hex letters to lowercase for execution/display. Do not attempt to
expand or re-compress the address in v0.1.

### 7.4 ASCII hostname/domain grammar

Accept an ASCII DNS name with an optional single trailing root dot:

- after removing that trailing dot, total length 1–253;
- labels separated by `.`, each 1–63 characters;
- label is `[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?`, with the
  one-character case naturally allowed;
- no empty labels, underscore, leading/trailing hyphen, whitespace, slash,
  colon, or shell metacharacter;
- single-label hostnames are allowed because both Ping Host and DNS Lookup are
  specified for hostnames as well as domains;
- lowercase for normalized execution; preserve a valid trailing dot because it
  explicitly requests an absolute DNS name.

ASCII `xn--` A-labels that satisfy this label grammar are accepted as already
encoded names. Raw Unicode U-label input is deferred from v0.1. Although the
installed iputils reports IDN support, QML JavaScript does not provide a
locally verified IDNA2008/UTS #46 conversion API. Ad-hoc Unicode normalization
would create spoofing and inconsistent-resolution risks. The UI should say
“Internationalized names: enter the ASCII punycode form in v0.1.” A future
version may add raw IDNs only with a reviewed, already-available native IDNA
facility and explicit normalization tests.

## 8. System Health diagnostic

### 8.1 Check thresholds

Threshold endpoints are inclusive where stated. Values are calculated from
unrounded numbers; rounding is presentation only.

| Check | Healthy | Warning | Critical | Evidence |
|---|---|---|---|---|
| CPU utilization | `< 70%` | `70% to < 90%` | `>= 90%` | Aggregate `/proc/stat` delta over 1 second. |
| Normalized 1-min load | `< 0.70` | `0.70 to < 1.00` | `>= 1.00` | `/proc/loadavg` 1-min value divided by logical CPU count. Also display raw 1/5/15 load. |
| Memory availability | `>= 20%` | `10% to < 20%` | `< 10%` | `MemAvailable / MemTotal`; display used and swap as context. |
| Storage utilization | `< 80%` | `80% to < 90%` | `>= 90%` | Worst unique real filesystem, including root; label the triggering mount. |
| Failed services | `0` | `1–2` | `>= 3` | Combined visible system/user failed-unit count with scope. |
| systemd system state | `running` | `degraded`, `initializing`, or `starting` | `maintenance`, `stopping`, or `offline` | `systemctl is-system-running` text and documented exit result. `degraded` severity may be raised by failed-service count. |

CPU utilization and normalized load are separate checks: utilization is a
short sample, while load includes runnable/uninterruptible work over time. The
System Health summary includes both and does not call load “CPU percent.”

### 8.2 Status vocabulary

- `healthy`: valid evidence is within the healthy band.
- `warning`: valid evidence crossed a warning threshold or indicates degraded
  but not immediately critical state.
- `critical`: valid evidence crossed a critical threshold.
- `unavailable`: the source/tool does not exist, the platform legitimately
  lacks it, or permission prevents an optional observation.
- `error`: the source should have worked but execution, timeout, bounds, or
  parsing prevented a trustworthy answer.

`unavailable` and `error` are not numeric severities and never become green.

### 8.3 Deterministic summary algorithm

1. Take one diagnostic snapshot. Reuse values captured in that run; do not
   combine arbitrarily aged dashboard values. Maximum accepted age is 10 s for
   CPU/memory/load and 60 s for storage/services.
2. Evaluate all six checks independently and preserve their evidence.
3. Overall known severity is the worst of `critical > warning > healthy`.
4. Compute completeness separately: `complete`, `unavailable`, or `error`.
   Any error makes completeness `error`; otherwise any unavailable check makes
   it `unavailable`.
5. If a known check is critical, overall label is `critical`, with an
   additional “diagnostic incomplete” notice when completeness is not complete.
   Otherwise an error produces overall `error`; otherwise a warning produces
   `warning`; otherwise unavailable produces `unavailable`; only six healthy,
   complete checks produce overall `healthy`.
6. Never average severities, infer causes, or claim the machine is healthy when
   a required check could not run.

## 9. Network Diagnostic

The diagnostic is user-triggered and sequential. Each stage is shown as
pending, running, passed, warning/failed, skipped, unavailable, or error. A
failed prerequisite skips only stages that cannot be meaningfully attempted;
independent later stages may still run to provide useful evidence.

### 9.1 Stages and evidence

1. **Interface state**
   - Evidence: `ip -j route show default` selects the lowest-metric default
     route; `ip -j link show` supplies `operstate`, `UP`, and `LOWER_UP`.
   - Pass: chosen non-loopback interface is administratively up and has carrier
     (`LOWER_UP`), or is a point-to-point interface with a usable default route.
   - Fail: no candidate interface, administratively down, or carrier absent.

2. **Local IP**
   - Evidence: `prefsrc` from the chosen default route and global-unicast
     `addr_info` entries from `ip -j address show` on that interface.
   - Pass: at least one valid non-loopback address exists. Report IPv4/IPv6
     separately.
   - Fail: interface exists but has no usable local address.

3. **Default gateway/route**
   - Evidence: default route destination, gateway, device, metric, protocol.
   - Pass: a usable default route exists. For an on-link or point-to-point
     default without a next-hop address, pass the route check but mark gateway
     address unavailable.
   - Fail: no default route for either family.

4. **Gateway reachability**
   - Evidence: `ping -n -c 2 -W 1 -w 3 -- <validated gateway>` and parsed
     transmitted/received/loss/latency.
   - Pass: at least one reply.
   - Warning: route exists but no reply; explicitly state that gateways may
     block ICMP, so this is not proof the gateway is down.
   - Skipped: route has no explicit gateway address.

5. **DNS resolution**
   - Evidence: separate A and AAAA JSON queries for `example.com`, an IANA
     reserved example domain, through the configured resolver.
   - Pass: at least one valid address answer. An empty family is allowed if the
     other succeeds.
   - Fail: resolver returns a definite not-found/failure; error/unavailable if
     the resolver process itself cannot be assessed.
   - The target is code-owned, shown to the user, and not configurable text.

6. **Internet reachability**
   - Definition for v0.1: at least one successful ICMP echo reply to a fixed
     public anycast address, independent of DNS. This tests outbound IP
     reachability, not general web/TLS availability.
   - Probe in fixed order, stopping on first success: Cloudflare (`1.1.1.1` or
     `2606:4700:4700::1111`), Quad9 (`9.9.9.9` or `2620:fe::fe`), then Google
     (`8.8.8.8` or `2001:4860:4860::8888`), each with one packet and a short
     timeout. Select only a family for which the earlier stages found a local
     address and default route; on dual-stack systems try IPv4 then IPv6 for a
     provider before advancing. These independently operated targets avoid
     making failure depend on one third-party service while stopping early to
     limit traffic. The sequence and set remain fixed and reviewable.
   - Pass: any target replies; retain which target and latency as evidence.
   - Warning: all fail. State that ICMP filtering can produce this result even
     when some internet applications work. Do not claim “internet is down.”

The installed NetworkManager configuration uses a single Arch connectivity URL
(`/usr/lib/NetworkManager/conf.d/20-connectivity.conf:1-2`). It is useful as an
optional displayed hint through `Quickshell.Networking`, but it is not the
primary v0.1 internet test because that would depend on one HTTP endpoint and
NetworkManager policy. The three-target numeric probe avoids DNS coupling and
single-provider dependence without adding curl as a requirement.

The diagnostic sends only ordinary, user-triggered DNS/ICMP probes. It stores
nothing remotely or persistently, adds no identifiers, performs no background
probe, and includes no telemetry. The UI should disclose the fixed public
targets before or alongside the run.

### 9.2 Approximate failure location

The summary reports the earliest meaningful non-pass stage, with careful copy:

| First failing stage | Summary wording |
|---|---|
| Interface | “No usable network link was observed.” |
| Local IP | “The link is present, but no usable local address was observed.” |
| Default route | “Local addressing exists, but no default route was observed.” |
| Gateway ping | “The gateway did not answer ICMP; it may be unreachable or filtering ping.” |
| DNS | “IP routing may work, but the configured resolver did not return an address.” |
| Public ping | “DNS and local routing checks passed, but the public ICMP probes did not answer.” |

This is localization of observed failure, not causal diagnosis.

## 10. Search and keyboard UX

### 10.1 Search model

Build a display `ListModel` from the catalog; do not filter delegates ad hoc.
Normalize to lowercase and split the trimmed query on whitespace. Every term
must match at least one of name, keywords, category, or description.

Use deterministic tiers adapted from the native menu:

1. exact display name;
2. name prefix;
3. name substring;
4. keyword/category exact or prefix match;
5. description word-prefix match;
6. stable catalog order as tie-breaker.

Reset selection to the first result after the query changes. A zero-result
query shows `No matches for “…”`; an impossible empty catalog/source uses a
different unavailable/error message. Search is entirely local and immediate.

### 10.2 Keys and focus

- Printable unmodified characters append to search when the tool list is
  active. Backspace edits it.
- Up/Down moves one result and wraps at the ends, matching the native menu.
- Enter/Return activates the selected row. If an action needs input, it opens
  the input view and focuses its field; it does not execute an empty value.
- Escape in an input editor returns to that action; Escape in a result returns
  to the tool list; Escape with a nonempty tool search clears it first; Escape
  at the unfiltered root dismisses Command Center.
- Pointer hover and keyboard share `selectedIndex`; pointer movement, not a
  stationary cursor exposed by reflow, changes selection.
- Use `ListView.positionViewAtIndex(..., ListView.Contain)` after selection and
  keep the selected row visible.

Use a root key catcher with `Keys.priority: Keys.BeforeItem`, following the
native menu. When a Ping/DNS `TextField` has `activeFocus`, set the catcher to a
blocked/editor mode so text editing receives navigation keys appropriately;
handle Escape and submit explicitly at the editor boundary. After opening the
overlay or returning from a child view, call `forceActiveFocus()` through
`Qt.callLater()` because the surface was previously unmapped.

No global keybinding is added or changed.

## 11. Theming and presentation

Use the shell singletons and components already available through
`qs.Commons` and `qs.Ui`:

- surface: `Color.menu.background`, `Color.menu.border`, `Color.menu.scrim`;
- primary text: `Color.menu.text`;
- selection: `Color.menu.selectedBackground`, `selectedText`, and
  `selectedBorder` via shared border helpers;
- semantic problem color: `Color.urgent`; subdued text via `Color.muted` or a
  theme-derived alpha of the foreground;
- typography: `Style.font.menuFamily` and named size tokens;
- geometry: `Style.cornerRadius`, `Style.gapsOut`, `Style.space(...)`, and
  `Style.spacing.*`;
- interactive states: `Style.normal/hover/selected/focus*` helpers and
  `Border.controlSpec`/`Border.localOrSurfaceSpec`;
- reusable controls: `BorderSurface`, `TextField`, `Button`, and
  `PanelKeyCatcher` where their behavior fits.

Prefer `BorderSurface` to a hand-built one-pixel rectangle border so themes
with custom side widths/alphas remain correct. Use `Text.PlainText` for every
dynamic label. Status must be communicated by text/icon as well as color, so a
theme's palette or color-vision difference does not erase meaning.

Do not add Command Center-specific color literals, Cyberdeck colors, or theme
files. A fixed translucent black scrim is used by some specialized first-party
overlays, but Command Center already has and should retain `Color.menu.scrim`
so it follows the user's active theme.

### 11.1 State presentation

Every feature view has mutually exclusive top-level states:

- loading: progress affordance plus “Checking …”; retain no unlabeled old
  value as current;
- success: structured cards/table and observation timestamp;
- empty: feature-specific explanation such as “No failed services”;
- unavailable: name the unavailable source and what cannot be shown;
- timeout: name the timed-out check and offer retry;
- error: concise mapped message, source label, and retry;
- partial: show valid fields and an explicit unavailable-fields notice.

The “underlying command” line is generated from the code-owned request
definition or a static learning label. User input is displayed quoted as data,
never assembled into executable-looking shell text without clear escaping.

## 12. Security and threat model

### 12.1 Assets and trust boundaries

Command Center runs unsandboxed inside the long-lived user `omarchy-shell`
process, as documented in `/usr/share/omarchy/shell/README.md`. Therefore a
plugin defect can affect the user's session. Trust boundaries are:

- typed user input → validator;
- action ID → code-owned service mapping;
- local kernel/system tools → untrusted/malformed output parser;
- service result → plain-text presentation;
- plugin close/hot reload → child-process cleanup.

### 12.2 Threats and controls

| Threat | Control |
|---|---|
| Shell/command injection | No shell invocation; no executable strings in metadata; fixed absolute executable; argv array; strict input grammar; `--` before input where supported. |
| Option injection | Reject leading `-`, whitespace, ports, zones, and non-grammar characters; append validated input only in its fixed final slot. |
| PATH/executable shadowing | Use reviewed absolute `/usr/bin/...` paths. Never accept executable names or paths from config, output, environment, payload, or catalog metadata. |
| Environment influence | Prefer JSON; force C locale for text; disable pagers/colors; keep only necessary inherited session environment and never derive env values from input. |
| Malicious/malformed output | Strict schema/type/range validation, output/row/field caps, immutable primitive copies, plain-text rendering, control-character stripping, no fallback from claimed JSON to permissive text. |
| Stale-output race | Monotonic run IDs, explicit canceled flag, wait for exit/streams, queue replacements, ignore all stale callbacks. |
| Hanging process / denial of service | Per-command and whole-diagnostic deadlines, TERM then KILL, four-child concurrency cap, bounded output, no rapid automatic retry. |
| Excessive local work | No recursive disk scan, bounded socket rows, conservative refresh intervals, user-triggered diagnostics. |
| Privilege escalation | Never invoke sudo, pkexec, systemd mutations, capabilities helpers, or privileged helper scripts. Permission loss becomes unavailable/error. |
| Accidental state change | Allowlist only read verbs/flags. Review exact argv definitions against the matrix. No `ss -K`, `systemctl start/stop/reset-failed`, `resolvectl` setters, `ip` mutators, or writes to `/proc`/`/sys`. |
| Sensitive data disclosure | Do not collect machine ID, hardware serial/UUID, environment, command lines beyond the limited `ss -p` owner metadata, or file contents outside named sources. Do not persist results. |
| Network privacy/telemetry | Only explicit Ping/DNS/Network Diagnostic actions send traffic; fixed diagnostic targets are disclosed; no background probe, analytics, identifier, upload, or result persistence. |
| Misleading diagnosis | Separate execution status from severity, preserve evidence, qualify ICMP failures, expose partial/unavailable checks, and never claim AI diagnosis. |

### 12.3 Read-only allowlist review

Before implementation merge, enumerate every literal executable/argv template
in one review table and verify that each command is observational. The v0.1
allowlist is limited to reads from `/proc`, `/sys`, `/etc/os-release`, and
`/etc/resolv.conf`, plus read-only invocations of `/usr/bin/ip`, `/usr/bin/ss`,
`/usr/bin/systemctl`, `/usr/bin/resolvectl`, `/usr/bin/ping`,
`/usr/bin/findmnt`, `/usr/bin/df`, `/usr/bin/hostnamectl`, `/usr/bin/uname`, and
`/usr/bin/getent` as described above. A tool being on this list does not allow
other verbs or flags.

No feature may execute the educational `displayCommand` string.

## 13. Recommended implementation sequence

1. Add pure result constructors, validation, and parser modules with fixture
   tests for valid, empty, malformed, oversized, partial, and permission cases.
2. Add `ProcessRunner.qml` with run IDs, separate argv, absolute path policy,
   stdout/stderr settlement, timeout, TERM/KILL, bounds, and destruction cleanup.
   Verify races before connecting real views.
3. Add the command catalog and local search/ranking tests. Catalog actions route
   only to typed controller methods.
4. Implement canonical system snapshots and their four System result views;
   reuse those snapshots for the dashboard.
5. Implement canonical network snapshots and Listening Ports, with fixtures
   covering IPv4, bracketless/bracketed `ss` endpoints, wildcard endpoints,
   IPv6, scope IDs in tool output, and missing process metadata.
6. Implement Ping and DNS input views only after validator tests pass; verify
   the final process receives one safe argv element for the target.
7. Implement System Health from snapshot result objects, then add threshold
   boundary tests (just below/at/above every boundary) and incomplete-run tests.
8. Implement Network Diagnostic as a visible stage state machine with fixture
   outcomes and a whole-run cancellation/timeout test.
9. Compose dashboard/search/result navigation in `Menu.qml`, then apply native
   focus, keyboard, empty/loading/error, and theme patterns.
10. Perform an explicit read-only security review, plugin validation, QML lint
    or available tests, live close/reopen/cancel tests, and theme checks across
    at least one light and one dark Omarchy theme.

## 14. Verification plan for implementation

At minimum, later implementation verification should cover:

- validator property/boundary fixtures including option-looking input, invalid
  dotted decimal, every IPv6 compression shape, overlong labels, Unicode, and
  punycode A-labels;
- parser fixtures captured from the installed tool versions plus malformed,
  truncated, enormous, empty, localized, and permission-denied variants;
- callback permutations where exit arrives before/after stdout/stderr finish;
- close, replace, reopen, timeout, TERM-resistant process, and plugin
  destruction lifecycle cases with no stale UI update;
- exact diagnostic thresholds and overall completeness precedence;
- no process execution during search or invalid input;
- static review finding no shell, eval, sudo/pkexec, mutating verbs, or dynamic
  executable path;
- keyboard behavior and focus after mapping;
- themed rendering without plugin-specific color literals.

## 15. Resolved decisions and remaining questions

Resolved for v0.1:

- native Quickshell `Process` with absolute executable plus separate argv;
- asynchronous, bounded, generation-aware execution and explicit cleanup;
- the data sources and fallback semantics in section 6;
- ASCII hostname/domain plus strict IPv4/IPv6 input; raw Unicode IDNs deferred;
- numeric health thresholds and deterministic aggregation;
- a staged network diagnostic using kernel evidence, the configured resolver,
  and multiple public anycast ICMP targets;
- native menu-style search, cursor, keyboard, focus, and theme tokens;
- no added dependency, telemetry, privilege path, or state-changing action.

Additional resolved decisions for v0.1:

- **Failed service scope:** query both the system and user systemd managers.
  Keep each result explicitly labeled as System or User. The dashboard may
  show a combined failed-service total, but detailed results must distinguish
  System and User failures.
- **Public diagnostic probes:** approve the fixed anycast ICMP targets in the
  proposed order: Cloudflare (`1.1.1.1` or `2606:4700:4700::1111`), Quad9
  (`9.9.9.9` or `2620:fe::fe`), then Google (`8.8.8.8` or
  `2001:4860:4860::8888`). Disclose the targets to the user. Describe the
  result only as public IP/ICMP reachability evidence; a failed ICMP probe
  must never be presented as proof that the internet is down.
- **Dashboard refresh:** while Command Center is open, refresh CPU at
  approximately 2-second intervals; memory, load, and network approximately
  every 5 seconds; and storage and failed services no more frequently than
  every 30 seconds. Advance uptime locally after an authoritative initial
  reading. Stop all polling, timers, and processes when Command Center closes.

These decisions do not loosen the read-only or structured-execution boundary.
