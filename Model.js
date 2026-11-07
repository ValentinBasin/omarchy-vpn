.pragma library

// Pure helpers for the VPN widget. Kept free of QML types so they can be
// unit-tested with plain Node (see tests/model.test.mjs).

// NetworkManager VPN plugins (OpenVPN, L2TP, OpenConnect, ...) report "vpn";
// WireGuard profiles have their own type.
var vpnTypes = ["vpn", "wireguard"]

// Splits one line of `nmcli -t` output into fields, honouring the "\:" and
// "\\" escapes nmcli uses in terse mode.
function splitTerse(line) {
  var fields = []
  var current = ""
  for (var i = 0; i < line.length; i++) {
    var c = line[i]
    if (c === "\\" && i + 1 < line.length) {
      current += line[++i]
    } else if (c === ":") {
      fields.push(current)
      current = ""
    } else {
      current += c
    }
  }
  fields.push(current)
  return fields
}

// Parses `nmcli -t -f TYPE,UUID,STATE,NAME connection show` into
// [{ type, uuid, state, name }], VPN profiles only, sorted by name.
// state is "activated", "activating", "deactivating" or "" (inactive).
function parseVpns(raw) {
  var result = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    if (lines[i] === "") continue
    var f = splitTerse(lines[i])
    if (f.length < 4 || vpnTypes.indexOf(f[0]) < 0 || f[1] === "") continue
    result.push({ type: f[0], uuid: f[1], state: f[2], name: f[3] })
  }
  result.sort(function(a, b) { return a.name.localeCompare(b.name) || a.uuid.localeCompare(b.uuid) })
  return result
}

function namesInState(vpns, state) {
  var names = []
  for (var i = 0; i < vpns.length; i++) if (vpns[i].state === state) names.push(vpns[i].name)
  return names
}

// Notification bodies may be interpreted as markup by the notification daemon.
function escapeMarkup(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

// True when nmcli failed because nobody supplied the VPN password, which
// happens when no NetworkManager secret agent (e.g. nm-applet) is running.
function isSecretsError(stderr) {
  return /secrets were required|no secrets|no agents were available/i.test(String(stderr || ""))
}
