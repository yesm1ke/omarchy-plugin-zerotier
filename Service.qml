import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  property bool installed: false
  property bool infoOk: false
  property bool tokenError: false
  property bool online: false
  property bool tcpFallback: false

  // Optimistic service state so the switch throws the instant it is clicked.
  // _desired is -1 while we just mirror reality, or 0/1 while a toggle catches up.
  property int _desired: -1
  readonly property bool active: _desired === -1 ? infoOk : (_desired === 1)

  property bool refreshing: false
  property string nodeAddress: ""
  property string version: ""
  // This node's friendly name as registered in ZeroTier Central, matched from
  // the member list by node address. Empty until Central data arrives (or when
  // no Central token is configured) — the panel falls back to nodeAddress.
  readonly property string localName: {
    var addr = String(nodeAddress || "")
    if (addr === "" || members.length === 0) return ""
    for (var i = 0; i < members.length; i++) {
      var m = members[i]
      if (m && String(m.nodeId || "") === addr && String(m.name || "") !== "")
        return String(m.displayName || m.name)
    }
    return ""
  }
  property string statusText: "Checking…"
  property string lastError: ""
  property string actionStatus: ""

  property var networks: []
  property var peers: []

  // ZeroTier Central member list (names + managed IPs). Populated only when a
  // Central API token is available: the mode-0600 "central-token" file in
  // localDir wins, with the legacy "apiToken" plugin setting as fallback.
  property string centralToken: ""
  readonly property bool centralConfigured: centralToken !== ""
  property var members: []
  property string membersError: ""
  property bool membersLoading: false
  property var _memberJobs: []
  property var _membersAccum: []
  property var _memberJobNet: null
  property string _memberOut: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  // Local zerotier-cli home. FIXED at ~/.config/zerotier on purpose: the
  // privileged setup step re-derives this same path from the invoking uid's
  // account entry, so no plugin setting or environment value may steer where
  // root writes. This copy is only ever used unprivileged (zerotier-cli -D
  // plus the Central token file, all as the normal user).
  readonly property string localDir: (Quickshell.env("HOME") || "") + "/.config/zerotier"
  readonly property string _dFlag: "-D" + localDir
  readonly property string systemAuthToken: "/var/lib/zerotier-one/authtoken.secret"
  // Hard cap for ZeroTier Central response bodies: enforced by curl
  // --max-filesize in _centralFetchScript and re-checked in
  // memberProcess.onExited before any JSON parsing.
  readonly property int membersMaxBytes: 1048576
  // Fetch a Central member list without ever placing the API token in process
  // arguments. The token arrives on stdin (one line, written by onStarted),
  // is scrubbed to a safe charset, and only lands in a mode-0600 curl config
  // file that curl reads directly. Argv stays constant apart from the
  // (non-secret) network id, and curl's argv only names the config file.
  readonly property string _centralFetchScript: [
    "set -eu",
    "net=\"${1:-}\"",
    "case \"$net\" in *[!0-9a-fA-F]*|\"\") echo \"central: refusing bad network id\" >&2; exit 2;; esac",
    "[ \"${#net}\" -eq 16 ] || { echo \"central: refusing bad network id\" >&2; exit 2; }",
    "token=\"\"; IFS= read -r token || true",
    "token=\"${token//[[:space:]]/}\"",
    "clean=\"$(printf '%s' \"$token\" | tr -d -c 'A-Za-z0-9._~-')\"",
    "[ -n \"$token\" ] && [ \"$clean\" = \"$token\" ] || { echo \"central: refusing bad token\" >&2; exit 4; }",
    "tmp=\"$(mktemp \"${TMPDIR:-/tmp}/zt-central-curl.XXXXXX\")\"",
    "trap 'rm -f -- \"$tmp\" 2>/dev/null || true' EXIT INT TERM HUP",
    "chmod 600 \"$tmp\"",
    "{",
    "printf 'header = \"Authorization: token %s\"\\n' \"$token\"",
    "printf 'header = \"Accept: application/json\"\\n'",
    "printf 'silent\\nshow-error\\nmax-time = \"12\"\\nmax-filesize = \"1048576\"\\n'",
    "printf 'url = \"https://api.zerotier.com/api/v1/network/%s/member\"\\n' \"$net\"",
    "} > \"$tmp\"",
    "chmod 600 \"$tmp\"",
    "exec curl -K \"$tmp\""
  ].join("\n")
  // Store the pasted Central token in the mode-0600 central-token file with
  // the same stdin discipline: the secret is piped in, never part of the
  // shell command, and staged via mktemp + mv -T so a destination symlink is
  // replaced, never followed.
  readonly property string _centralSaveScript: [
    "set -eu",
    "base=\"${HOME:-}\"",
    "[ -n \"$base\" ] || exit 1",
    "dir=\"$base/.config/zerotier\"",
    "file=\"$dir/central-token\"",
    "if [ -L \"$file\" ]; then echo \"central: refusing symlink\" >&2; exit 1; fi",
    "if [ -e \"$file\" ] && [ ! -f \"$file\" ]; then echo \"central: refusing non-file\" >&2; exit 1; fi",
    "token=\"\"; IFS= read -r token || true",
    "token=\"${token//[[:space:]]/}\"",
    "clean=\"$(printf '%s' \"$token\" | tr -d -c 'A-Za-z0-9._~-')\"",
    "[ -n \"$token\" ] && [ \"$clean\" = \"$token\" ] || exit 1",
    "[ \"${#token}\" -le 4096 ] || exit 1",
    "umask 077",
    "mkdir -p \"$dir\"",
    "[ ! -L \"$dir\" ] && [ -d \"$dir\" ] || exit 1",
    "tmp=\"$(mktemp \"$dir/.central-token.XXXXXX\")\"",
    "trap 'rm -f -- \"$tmp\" 2>/dev/null || true' EXIT INT TERM HUP",
    "printf '%s' \"$token\" > \"$tmp\"",
    "chmod 600 \"$tmp\"",
    "mv -T -- \"$tmp\" \"$file\"",
    "chmod 600 \"$file\""
  ].join("\n")
  // One privileged step, run through pkexec: copy the daemon's local API
  // token into the invoking user's ~/.config/zerotier so zerotier-cli can run
  // unprivileged afterwards. Deliberately CONSTANT — no settings, no
  // environment, no arguments flow into it:
  //  - user/home come from PKEXEC_UID (set by pkexec) via id/getent, never
  //    from $USER/$HOME or plugin settings;
  //  - the destination is fixed to <home>/.config/zerotier and every path
  //    component is rejected if it is a symlink or a non-directory;
  //  - directories are created individually (no mkdir -p across the tree),
  //    files are staged with mktemp and installed with mv -T (replacing a
  //    destination symlink instead of following it), and ownership is set
  //    per path — never a recursive chown.
  readonly property string _localAccessScript: [
    "set -eu",
    "src=\"/var/lib/zerotier-one/authtoken.secret\"",
    "uid=\"${PKEXEC_UID:-}\"",
    "case \"$uid\" in ''|*[!0-9]*) echo \"setup: refusing without PKEXEC_UID\" >&2; exit 1;; esac",
    "user=\"$(id -un \"$uid\" 2>/dev/null)\" || { echo \"setup: unknown uid\" >&2; exit 1; }",
    "[ -n \"$user\" ] || { echo \"setup: unknown uid\" >&2; exit 1; }",
    "home=\"$(getent passwd \"$user\" | cut -d: -f6)\"",
    "case \"$home\" in /*) ;; *) echo \"setup: refusing bad home\" >&2; exit 1;; esac",
    "[ \"$home\" != \"/\" ] || { echo \"setup: refusing bad home\" >&2; exit 1; }",
    "[ -d \"$home\" ] && [ ! -L \"$home\" ] || { echo \"setup: refusing bad home\" >&2; exit 1; }",
    "owner=\"$(id -un \"$uid\"):$(id -gn \"$uid\")\" || exit 1",
    "cfg=\"$home/.config\"",
    "dir=\"$cfg/zerotier\"",
    "for p in \"$cfg\" \"$dir\"; do",
    "if [ -L \"$p\" ]; then echo \"setup: refusing symlink at $p\" >&2; exit 1; fi",
    "if [ -e \"$p\" ] && [ ! -d \"$p\" ]; then echo \"setup: refusing non-directory at $p\" >&2; exit 1; fi",
    "done",
    "[ -r \"$src\" ] || { echo \"setup: daemon token not found\" >&2; exit 1; }",
    "umask 077",
    "tmp1=\"\"; tmp2=\"\"",
    "trap 'rm -f -- \"$tmp1\" \"$tmp2\" 2>/dev/null || true' EXIT INT TERM HUP",
    "if [ ! -e \"$cfg\" ]; then mkdir -m 0700 \"$cfg\"; chown \"$owner\" \"$cfg\"; fi",
    "if [ ! -e \"$dir\" ]; then mkdir -m 0700 \"$dir\"; chown \"$owner\" \"$dir\"; fi",
    "for p in \"$cfg\" \"$dir\"; do",
    "[ ! -L \"$p\" ] && [ -d \"$p\" ] || { echo \"setup: refusing unsafe path $p\" >&2; exit 1; }",
    "done",
    "chmod 0700 \"$dir\"",
    "chown \"$owner\" \"$dir\"",
    "tmp1=\"$(mktemp \"$dir/.authtoken.XXXXXX\")\"",
    "cat -- \"$src\" > \"$tmp1\"",
    "chmod 0600 \"$tmp1\"",
    "chown \"$owner\" \"$tmp1\"",
    "mv -T -- \"$tmp1\" \"$dir/authtoken.secret\"",
    "tmp2=\"$(mktemp \"$dir/.port.XXXXXX\")\"",
    "printf '9993' > \"$tmp2\"",
    "chmod 0600 \"$tmp2\"",
    "chown \"$owner\" \"$tmp2\"",
    "mv -T -- \"$tmp2\" \"$dir/zerotier-one.port\"",
    "systemctl start zerotier-one.service || true"
  ].join("\n")
  readonly property bool busy: whichProcess.running || infoProcess.running || networksProcess.running
    || peersProcess.running || actionProcess.running || toggleProcess.running || setupProcess.running
  property bool savingCentralToken: false

  property string _infoOut: ""
  property string _infoErr: ""
  property string _networksOut: ""
  property string _peersOut: ""
  property string _actionOut: ""
  property string _actionErr: ""
  property string _toggleErr: ""

  signal networksChanged2()
  signal peersChanged2()
  signal membersChanged2()

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function elide(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 160 ? value.substring(0, 157) + "…" : value
  }

  function copyToClipboard(value) {
    var text = String(value || "")
    if (text === "") return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(text) + " | wl-copy"])
    actionStatus = "Copied"
    actionStatusTimer.restart()
  }

  function refresh() {
    if (!installed) {
      if (!whichProcess.running) {
        refreshing = true
        whichProcess.command = ["which", "zerotier-cli"]
        whichProcess.running = true
      }
      return
    }
    // Note: the _*Out caches are deliberately NOT cleared here. If onExited
    // races ahead of the StdioCollector's onStreamFinished (it occasionally
    // does even with waitForEnd), the handler falls back to the previous
    // poll's output instead of parsing an empty string as a hard failure.
    if (!infoProcess.running) {
      refreshing = true
      infoProcess.command = ["zerotier-cli", _dFlag, "-j", "info"]
      infoProcess.running = true
    }
    if (!networksProcess.running) {
      networksProcess.command = ["zerotier-cli", _dFlag, "-j", "listnetworks"]
      networksProcess.running = true
    }
    if (!peersProcess.running) {
      peersProcess.command = ["zerotier-cli", _dFlag, "-j", "peers"]
      peersProcess.running = true
    }
    if (!tokenFileProcess.running) {
      tokenFileProcess.command = ["bash", "-c",
        "cat " + Util.shellQuote(localDir + "/central-token") + " 2>/dev/null || true"]
      tokenFileProcess.running = true
    }
    if (!pollWatchdog.running) pollWatchdog.start()
  }

  // Walk every joined network's Central member list, one fetch per network,
  // and merge the rows. Kicked after each networks refresh. Each fetch runs
  // _centralFetchScript, which receives the API token on stdin and lets curl
  // read it from a mode-0600 config file — the secret never appears in argv.
  function refreshMembers() {
    if (!centralConfigured || networks.length === 0) {
      _memberJobs = []
      if (members.length > 0) { members = []; membersChanged2() }
      return
    }
    if (memberProcess.running) return
    var jobs = []
    for (var i = 0; i < networks.length; i++)
      if (networks[i] && Model.looksLikeNetworkId(networks[i].id)) jobs.push(networks[i])
    _memberJobs = jobs
    _membersAccum = []
    membersLoading = true
    startNextMemberJob()
  }

  function startNextMemberJob() {
    if (_memberJobs.length === 0) {
      members = Model.sortMembers(_membersAccum)
      membersLoading = false
      membersChanged2()
      return
    }
    var net = _memberJobs[0]
    _memberJobs = _memberJobs.slice(1)
    _memberJobNet = net
    _memberOut = ""
    // Token travels on stdin (memberProcess.onStarted), never in argv; the
    // only argument is the non-secret network id, validated by the script.
    memberProcess._pendingToken = centralToken
    memberProcess.command = ["bash", "-c", _centralFetchScript, "zerotier-central", String(net.id)]
    memberProcess.running = true
  }

  function resetUnavailable(message) {
    infoOk = false
    online = false
    tcpFallback = false
    _desired = -1
    nodeAddress = ""
    version = ""
    networks = []
    peers = []
    members = []
    _memberJobs = []
    statusText = message
  }

  // zerotier-cli occasionally errors for a single poll — the daemon is briefly
  // busy, or the watchdog reaped a slow call — and is fine again on the next
  // one. Absorb a couple of misses before tearing the panel down to an empty
  // "service stopped" state.
  property int _infoFailStreak: 0
  readonly property int _failToleranceCount: 3

  function applyInfo(exitCode, stdout, stderr) {
    refreshing = false
    var parsed = Model.parseInfo(stdout)
    // A clean parse (code 200) is authoritative — never let a stale stderr
    // from a previous poll flag a token error over a good result.
    var tokenBad = parsed.code === 401
      || (!parsed.ok && (Model.tokenError(stderr) || Model.tokenError(stdout)))

    if (tokenBad) {
      _infoFailStreak = 0
      tokenError = true
      resetUnavailable("Auth token not readable")
      lastError = "ZeroTier auth token is not readable by your user — toggle on to authorize."
      return
    }

    if (exitCode !== 0 || !parsed.ok) {
      _infoFailStreak++
      // Keep the last good snapshot on screen while we ride out the blip.
      if (_infoFailStreak < _failToleranceCount && (infoOk || nodeAddress !== "")) return
      resetUnavailable(exitCode !== 0 ? "Service not responding" : "Status error")
      lastError = exitCode !== 0
        ? elide(stderr || stdout || "zerotier-cli info failed")
        : (parsed.message || "Could not parse zerotier-cli info")
      return
    }

    _infoFailStreak = 0
    tokenError = false
    infoOk = true
    nodeAddress = parsed.address
    version = parsed.version
    online = parsed.online
    tcpFallback = parsed.tcpFallback
    if (_desired !== -1 && infoOk === (_desired === 1)) _desired = -1
    statusText = parsed.online ? "Online" : "Offline"
    lastError = ""
  }

  function applyNetworks(exitCode, stdout) {
    // A failed poll leaves the previous list in place rather than flashing
    // "no networks". An exit-0 empty array is a real "left all networks".
    if (exitCode !== 0) return
    networks = Model.parseNetworks(stdout)
    networksChanged2()
    refreshMembers()
  }

  function applyPeers(exitCode, stdout) {
    if (exitCode !== 0) return
    peers = Model.parsePeers(stdout, { leafOnly: true })
    peersChanged2()
  }

  function toggleService() {
    if (!installed) return
    // Turning "on" while the daemon's API token is unreadable means the widget
    // has nothing to talk to — the useful action there is to grant access.
    if (tokenError) { setupLocalAccess(); return }
    if (active) stopService()
    else startService()
  }

  // One privileged step: copy the daemon's local API token into the invoking
  // user's ~/.config/zerotier (+ port file) and make sure the service is
  // running, approved through the graphical polkit prompt. _localAccessScript
  // is fully constant — user, home and destination are derived from
  // PKEXEC_UID/account data inside the script, never from plugin settings.
  function setupLocalAccess() {
    if (setupProcess.running) return
    _toggleErr = ""
    actionStatus = "Authorizing ZeroTier access…"
    setupProcess.command = ["pkexec", "bash", "-c", _localAccessScript]
    setupProcess.running = true
  }

  // Save the ZeroTier Central API token the user pasted into the panel. No
  // privilege needed — it lives in the user's own config dir (mode 600).
  // The value travels on stdin (centralTokenSaveProcess.onStarted), so the
  // shell command never contains the secret.
  function saveCentralToken(token) {
    var value = String(token || "").trim().replace(/\s+/g, "")
    if (value === "" || centralTokenSaveProcess.running) return
    savingCentralToken = true
    actionStatus = "Saving token…"
    centralTokenSaveProcess._pending = value
    centralTokenSaveProcess.command = ["bash", "-c", _centralSaveScript]
    centralTokenSaveProcess.running = true
  }

  function startService() {
    if (toggleProcess.running) return
    _desired = 1
    _toggleErr = ""
    actionStatus = "Starting ZeroTier…"
    toggleProcess.command = ["pkexec", "systemctl", "start", "zerotier-one.service"]
    toggleProcess.running = true
  }

  function stopService() {
    if (toggleProcess.running) return
    _desired = 0
    _toggleErr = ""
    actionStatus = "Stopping ZeroTier…"
    toggleProcess.command = ["pkexec", "systemctl", "stop", "zerotier-one.service"]
    toggleProcess.running = true
  }

  function joinNetwork(id) {
    var networkId = String(id || "").trim().toLowerCase()
    if (!installed || !Model.looksLikeNetworkId(networkId) || actionProcess.running) return
    runAction(["zerotier-cli", _dFlag, "join", networkId], "Joining " + networkId + "…")
  }

  function leaveNetwork(id) {
    var networkId = String(id || "").trim().toLowerCase()
    if (!installed || networkId === "" || actionProcess.running) return
    runAction(["zerotier-cli", _dFlag, "leave", networkId], "Leaving " + networkId + "…")
  }

  function runAction(command, label) {
    if (actionProcess.running) return
    _actionOut = ""
    _actionErr = ""
    actionStatus = label || ""
    actionProcess.command = command
    actionProcess.running = true
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: startupRamp
    property int ticks: 0
    interval: 2000
    repeat: true
    running: true
    onTriggered: {
      ticks += 1
      if (root.infoOk || ticks >= 12) startupRamp.running = false
      else root.refresh()
    }
  }

  Timer {
    id: delayedRefresh
    interval: 700
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: pollWatchdog
    interval: 25000
    repeat: false
    onTriggered: {
      if (infoProcess.running) infoProcess.running = false
      if (networksProcess.running) networksProcess.running = false
      if (peersProcess.running) peersProcess.running = false
      if (memberProcess.running) { memberProcess.running = false; root._memberJobs = []; root.membersLoading = false }
      if (tokenFileProcess.running) tokenFileProcess.running = false
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: whichProcess
    running: false
    command: []
    onExited: function(exitCode) {
      root.installed = exitCode === 0
      if (root.installed) root.refresh()
      else {
        root.refreshing = false
        root.resetUnavailable("Not installed")
        root.lastError = "zerotier-cli is not installed or not on PATH."
      }
    }
  }

  Process {
    id: infoProcess
    running: false
    command: []
    stdout: StdioCollector { id: infoStdout; waitForEnd: true; onStreamFinished: root._infoOut = text }
    stderr: StdioCollector { id: infoStderr; waitForEnd: true; onStreamFinished: root._infoErr = text }
    onExited: function(exitCode) {
      root.applyInfo(exitCode, String(infoStdout.text || root._infoOut || ""), String(infoStderr.text || root._infoErr || ""))
    }
  }

  Process {
    id: networksProcess
    running: false
    command: []
    stdout: StdioCollector { id: networksStdout; waitForEnd: true; onStreamFinished: root._networksOut = text }
    onExited: function(exitCode) {
      root.applyNetworks(exitCode, String(networksStdout.text || root._networksOut || ""))
    }
  }

  Process {
    id: peersProcess
    running: false
    command: []
    stdout: StdioCollector { id: peersStdout; waitForEnd: true; onStreamFinished: root._peersOut = text }
    onExited: function(exitCode) {
      root.applyPeers(exitCode, String(peersStdout.text || root._peersOut || ""))
    }
  }

  Process {
    id: tokenFileProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: tokenFileStdout
      waitForEnd: true
      onStreamFinished: {
        var fileToken = String(text || "").trim()
        // Legacy "apiToken" plugin setting: memory-only fallback so existing
        // configs keep working. It is never placed in process arguments —
        // member fetches receive the effective token over stdin.
        var legacy = String(root.setting("apiToken", "")).trim().replace(/\s+/g, "")
        var next = fileToken !== "" ? fileToken : legacy
        if (next !== root.centralToken) {
          root.centralToken = next
          root.refreshMembers()
        }
      }
    }
  }

  Process {
    id: memberProcess
    running: false
    command: []
    stdinEnabled: true
    property string _pendingToken: ""
    stdout: StdioCollector { id: memberStdout; waitForEnd: true; onStreamFinished: root._memberOut = text }
    stderr: StdioCollector { id: memberStderr; waitForEnd: true }
    onStarted: {
      // Pipe the token to the fetch script's stdin: it never appears in the
      // curl argv or the shell command, so other local processes cannot
      // observe it through process inspection.
      if (memberProcess._pendingToken !== "") {
        memberProcess.write(memberProcess._pendingToken + "\n")
        memberProcess._pendingToken = ""
      }
    }
    onExited: function(exitCode) {
      var stdout = String(memberStdout.text || root._memberOut || "")
      // --max-time bounds duration but not size; reject oversized bodies
      // here, before parsing, as well as via curl --max-filesize.
      if (stdout.length > root.membersMaxBytes) {
        root.membersError = "Central response too large — ignored"
        root.startNextMemberJob()
        return
      }
      var parsed = Model.parseMembers(stdout, root._memberJobNet, root.membersMaxBytes)
      if (parsed.ok) {
        for (var i = 0; i < parsed.members.length; i++) root._membersAccum.push(parsed.members[i])
        root.membersError = ""
      } else if (exitCode !== 0) {
        root.membersError = "Could not reach ZeroTier Central"
      } else if (/authorization|unauthorized|forbidden|\"code\"\s*:\s*40/i.test(stdout)) {
        root.membersError = "ZeroTier Central token rejected"
      }
      root.startNextMemberJob()
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true; onStreamFinished: root._actionOut = text }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true; onStreamFinished: root._actionErr = text }
    onExited: function(exitCode) {
      var stdout = String(actionStdout.text || root._actionOut || "")
      var stderr = String(actionStderr.text || root._actionErr || "")
      if (exitCode !== 0) {
        root.lastError = root.elide(stderr || stdout || "ZeroTier command failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: toggleProcess
    running: false
    command: []
    stderr: StdioCollector { id: toggleStderr; waitForEnd: true; onStreamFinished: root._toggleErr = text }
    onExited: function(exitCode) {
      var stderr = String(toggleStderr.text || root._toggleErr || "")
      if (exitCode !== 0) {
        root._desired = -1
        root.lastError = root.elide(stderr || "Could not change the ZeroTier service")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: setupProcess
    running: false
    command: []
    stderr: StdioCollector { id: setupStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var stderr = String(setupStderr.text || "")
      if (exitCode === 0) {
        root.tokenError = false
        root.lastError = ""
        root.actionStatus = "ZeroTier access authorized"
      } else if (exitCode === 126 || exitCode === 127 || /dismiss|not authorized|cancel/i.test(stderr)) {
        root.actionStatus = "Authorization cancelled"
      } else {
        root.lastError = root.elide(stderr || "Could not authorize ZeroTier access")
        root.actionStatus = root.lastError
      }
      actionStatusTimer.restart()
      delayedRefresh.restart()
    }
  }

  Process {
    id: centralTokenSaveProcess
    running: false
    command: []
    stdinEnabled: true
    property string _pending: ""
    stderr: StdioCollector { id: centralSaveStderr; waitForEnd: true }
    onStarted: {
      // _pending is consumed in onExited, not here: clearing it now would
      // lose the value the success path below needs.
      if (centralTokenSaveProcess._pending !== "")
        centralTokenSaveProcess.write(centralTokenSaveProcess._pending + "\n")
    }
    onExited: function(exitCode) {
      root.savingCentralToken = false
      var saved = centralTokenSaveProcess._pending
      centralTokenSaveProcess._pending = ""
      if (exitCode === 0) {
        root.centralToken = saved
        root.membersError = ""
        root.actionStatus = "Central token saved"
        root.refreshMembers()
      } else {
        root.lastError = root.elide(String(centralSaveStderr.text || "") || "Could not save the Central token")
        root.actionStatus = root.lastError
      }
      actionStatusTimer.restart()
    }
  }
}
