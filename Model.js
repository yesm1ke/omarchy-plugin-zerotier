// Pure parsing helpers for `zerotier-cli -j` output. No QML imports here so the
// same code can be unit-tested with plain node.

function asArray(value) {
  return value && typeof value.length === "number" ? value : []
}

function stripPort(addr) {
  // zerotier path addresses look like "10.0.0.5/9993" or "[fe80::1]/9993".
  var text = String(addr || "")
  var slash = text.lastIndexOf("/")
  if (slash !== -1) text = text.substring(0, slash)
  if (text.charAt(0) === "[" && text.charAt(text.length - 1) === "]") text = text.slice(1, -1)
  return text
}

function ipOnly(cidr) {
  var text = String(cidr || "")
  var slash = text.indexOf("/")
  return slash === -1 ? text : text.substring(0, slash)
}

function isIPv6(ip) {
  return String(ip || "").indexOf(":") !== -1
}

function networkStatusLabel(status) {
  var value = String(status || "").toUpperCase()
  if (value === "OK") return "Connected"
  if (value === "REQUESTING_CONFIGURATION") return "Requesting config"
  if (value === "ACCESS_DENIED") return "Access denied"
  if (value === "NOT_FOUND") return "Not found"
  if (value === "PORT_ERROR") return "Port error"
  if (value === "CLIENT_TOO_OLD") return "Client too old"
  if (value === "AUTHENTICATION_REQUIRED") return "Auth required"
  return value ? value.charAt(0) + value.slice(1).toLowerCase().replace(/_/g, " ") : "Unknown"
}

function networkFromStatus(net) {
  var assigned = asArray(net.assignedAddresses).map(function(a) { return String(a) })
  var v4 = []
  var v6 = []
  for (var i = 0; i < assigned.length; i++) {
    var ip = ipOnly(assigned[i])
    if (ip === "") continue
    if (isIPv6(ip)) v6.push(ip)
    else v4.push(ip)
  }
  var name = String(net.name || "")
  return {
    id: String(net.id || net.nwid || ""),
    name: name,
    displayName: name !== "" ? name : String(net.id || net.nwid || "Unnamed network"),
    status: String(net.status || ""),
    statusLabel: networkStatusLabel(net.status),
    ok: String(net.status || "").toUpperCase() === "OK",
    type: String(net.type || ""),
    portDeviceName: String(net.portDeviceName || ""),
    portError: String(net.portError || "OK"),
    mac: String(net.mac || ""),
    mtu: net.mtu ? String(net.mtu) : "",
    dns: net.dns || null,
    assigned: assigned,
    ipv4: v4,
    ipv6: v6,
    primaryIp: v4.length > 0 ? v4[0] : (v6.length > 0 ? v6[0] : "")
  }
}

function bestPath(paths) {
  var list = asArray(paths)
  var preferred = null
  var active = null
  for (var i = 0; i < list.length; i++) {
    var p = list[i] || {}
    if (p.expired === true) continue
    if (p.preferred === true && !preferred) preferred = p
    if (p.active === true && !active) active = p
  }
  var chosen = preferred || active || (list.length > 0 ? list[0] : null)
  return chosen ? stripPort(chosen.address) : ""
}

function peerFromStatus(peer) {
  var role = String(peer.role || "").toUpperCase()
  var version = String(peer.version || "")
  if (version === "-1.-1.-1") version = ""
  return {
    address: String(peer.address || ""),
    role: role,
    roleLabel: role.charAt(0) + role.slice(1).toLowerCase(),
    version: version,
    latency: typeof peer.latency === "number" ? peer.latency : -1,
    endpoint: bestPath(peer.paths),
    direct: bestPath(peer.paths) !== ""
  }
}

// `zerotier-cli -j <cmd>` prints "<httpCode> <cmd> <json>" (e.g. "200 info {…}",
// "401 info {}"). Peel the prefix off and hand back the code plus the JSON body.
function cliResult(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { code: 0, body: "" }
  var match = text.match(/^(\d{3})\s+\S+\s*([\s\S]*)$/)
  if (match) return { code: parseInt(match[1], 10), body: String(match[2] || "").trim() }
  // Some builds / older versions emit bare JSON.
  if (text.charAt(0) === "{" || text.charAt(0) === "[") return { code: 200, body: text }
  return { code: 0, body: text }
}

function parseInfo(raw) {
  var res = cliResult(raw)
  if (res.code !== 200) return { ok: false, code: res.code, message: res.code === 401 ? "Auth token rejected" : "No response" }
  try {
    var data = JSON.parse(res.body)
    return {
      ok: true,
      code: 200,
      address: String(data.address || ""),
      version: String(data.version || ""),
      online: data.online === true,
      tcpFallback: data.tcpFallbackActive === true,
      planetWorldId: data.planetWorldId
    }
  } catch (e) {
    return { ok: false, code: res.code, message: "Bad info payload" }
  }
}

function parseNetworks(raw) {
  var res = cliResult(raw)
  if (res.code !== 200 || res.body === "") return []
  try {
    var data = JSON.parse(res.body)
    var out = []
    var list = asArray(data)
    for (var i = 0; i < list.length; i++) out.push(networkFromStatus(list[i] || {}))
    out.sort(function(a, b) { return String(a.displayName).localeCompare(String(b.displayName)) })
    return out
  } catch (e) {
    return []
  }
}

function parsePeers(raw, opts) {
  var options = opts || {}
  var res = cliResult(raw)
  if (res.code !== 200 || res.body === "") return []
  try {
    var data = JSON.parse(res.body)
    var out = []
    var list = asArray(data)
    for (var i = 0; i < list.length; i++) {
      var peer = peerFromStatus(list[i] || {})
      if (options.leafOnly === true && peer.role !== "LEAF") continue
      out.push(peer)
    }
    out.sort(function(a, b) {
      if (a.direct !== b.direct) return a.direct ? -1 : 1
      return String(a.address).localeCompare(String(b.address))
    })
    return out
  } catch (e) {
    return []
  }
}

function looksLikeNetworkId(value) {
  return /^[0-9a-fA-F]{16}$/.test(String(value || "").trim())
}

// ---- ZeroTier Central (my.zerotier.com) member list -------------------------
// GET https://api.zerotier.com/api/v1/network/{id}/member returns the same rows
// the web console shows: member name, managed IP assignments, last-seen, client
// version. The local daemon never has this, so it is the only way to show
// friendly names and ZeroTier IPs for machines this node is not directly peered
// with.

function memberFromCentral(raw, net) {
  var member = raw || {}
  var config = member.config || {}
  var ipAssignments = asArray(config.ipAssignments).map(function(x) { return String(x) })
  var v4 = [], v6 = []
  for (var i = 0; i < ipAssignments.length; i++) {
    if (isIPv6(ipAssignments[i])) v6.push(ipAssignments[i])
    else v4.push(ipAssignments[i])
  }
  var version = String(member.clientVersion || "").replace(/^v/i, "")
  if (version === "" && typeof config.vMajor === "number" && config.vMajor >= 0)
    version = config.vMajor + "." + config.vMinor + "." + config.vRev
  if (version === "-1.-1.-1" || /^0\.0\.0$/.test(version)) version = ""
  var lastOnline = Number(member.lastOnline || member.lastSeen || 0)
  var name = String(member.name || "")
  var nodeId = String(member.nodeId || config.address || member.id || "")
  return {
    nodeId: nodeId,
    name: name,
    displayName: name !== "" ? name : nodeId,
    networkId: net && net.id ? String(net.id) : String(member.networkId || ""),
    networkName: net && net.name ? String(net.name) : "",
    authorized: config.authorized === true,
    hidden: member.hidden === true,
    ips: v4.concat(v6),
    ip4: v4.length > 0 ? v4[0] : (v6.length > 0 ? v6[0] : ""),
    physicalAddress: String(member.physicalAddress || ""),
    version: version,
    lastOnline: lastOnline,
    online: lastOnline > 0 && (Date.now() - lastOnline) < 5 * 60 * 1000
  }
}

function parseMembers(raw, net, maxBytes) {
  var text = String(raw || "")
  // Hard response-size limit: --max-time bounds duration but not size, so
  // oversized bodies are rejected before parsing. Mirrors the curl
  // --max-filesize cap enforced when the body is fetched.
  var cap = typeof maxBytes === "number" && maxBytes > 0 ? maxBytes : 1048576
  if (text.length > cap) return { ok: false, members: [], truncated: true }
  text = text.trim()
  if (text === "" || text.charAt(0) !== "[") return { ok: false, members: [] }
  try {
    var list = asArray(JSON.parse(text))
    var out = []
    for (var i = 0; i < list.length; i++) {
      var m = memberFromCentral(list[i], net)
      if (m.hidden) continue
      out.push(m)
    }
    return { ok: true, members: out }
  } catch (e) {
    return { ok: false, members: [] }
  }
}

function sortMembers(list) {
  var out = (list || []).slice()
  out.sort(function(a, b) {
    if (a.online !== b.online) return a.online ? -1 : 1
    if (a.authorized !== b.authorized) return a.authorized ? -1 : 1
    return String(a.displayName).toLowerCase().localeCompare(String(b.displayName).toLowerCase())
  })
  return out
}

function agoLabel(ms) {
  var n = Number(ms || 0)
  if (!isFinite(n) || n <= 0) return ""
  var secs = Math.max(0, Math.floor((Date.now() - n) / 1000))
  if (secs < 45) return "just now"
  if (secs < 90) return "1 min ago"
  var mins = Math.floor(secs / 60)
  if (mins < 60) return mins + " min ago"
  var hours = Math.floor(mins / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  if (days < 30) return days + "d ago"
  return Math.floor(days / 30) + "mo ago"
}

function tokenError(text) {
  return /authtoken|not found or readable|permission denied|missing authentication token|401/i.test(String(text || ""))
}

if (typeof module !== "undefined") {
  module.exports = {
    cliResult: cliResult,
    stripPort: stripPort,
    ipOnly: ipOnly,
    isIPv6: isIPv6,
    networkStatusLabel: networkStatusLabel,
    networkFromStatus: networkFromStatus,
    peerFromStatus: peerFromStatus,
    bestPath: bestPath,
    parseInfo: parseInfo,
    parseNetworks: parseNetworks,
    parsePeers: parsePeers,
    looksLikeNetworkId: looksLikeNetworkId,
    tokenError: tokenError,
    memberFromCentral: memberFromCentral,
    parseMembers: parseMembers,
    sortMembers: sortMembers,
    agoLabel: agoLabel
  }
}
