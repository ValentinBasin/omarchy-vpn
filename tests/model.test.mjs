// Run with: node --test tests/
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync, readdirSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

const root = join(dirname(fileURLToPath(import.meta.url)), "..")

// Model.js is a QML JavaScript library; drop the pragma and evaluate it.
function loadModel() {
  const src = readFileSync(join(root, "Model.js"), "utf8").replace(/^\.pragma library\s*$/m, "")
  const names = ["vpnTypes", "splitTerse", "parseVpns", "namesInState", "escapeMarkup", "isSecretsError"]
  return new Function(`${src}\nreturn { ${names.join(", ")} }`)()
}

const Model = loadModel()

test("splitTerse unescapes nmcli terse fields", () => {
  assert.deepEqual(Model.splitTerse("vpn:u1::Office\\:Main"), ["vpn", "u1", "", "Office:Main"])
  assert.deepEqual(Model.splitTerse("vpn:u2::Back\\\\slash"), ["vpn", "u2", "", "Back\\slash"])
  assert.deepEqual(Model.splitTerse("a"), ["a"])
})

test("parseVpns keeps VPN and WireGuard profiles, sorted, with state", () => {
  const raw = [
    "802-11-wireless:w1::Home WiFi",
    "wireguard:g1:activated:Zeta",
    "vpn:v1:activating:Alpha",
    "vpn:v2::Office\\:Main",
    "vpn:::NoUuid",
    "",
  ].join("\n")
  assert.deepEqual(Model.parseVpns(raw), [
    { type: "vpn", uuid: "v1", state: "activating", name: "Alpha" },
    { type: "vpn", uuid: "v2", state: "", name: "Office:Main" },
    { type: "wireguard", uuid: "g1", state: "activated", name: "Zeta" },
  ])
})

test("parseVpns keeps duplicate names apart by UUID", () => {
  const vpns = Model.parseVpns("vpn:b::Same\nvpn:a::Same\n")
  assert.deepEqual(vpns.map(v => v.uuid), ["a", "b"])
})

test("parseVpns tolerates empty and garbage input", () => {
  assert.deepEqual(Model.parseVpns(""), [])
  assert.deepEqual(Model.parseVpns(undefined), [])
  assert.deepEqual(Model.parseVpns("not terse output"), [])
})

test("namesInState filters by connection state", () => {
  const vpns = Model.parseVpns("vpn:1:activated:A\nvpn:2:activating:B\nvpn:3::C\n")
  assert.deepEqual(Model.namesInState(vpns, "activated"), ["A"])
  assert.deepEqual(Model.namesInState(vpns, "activating"), ["B"])
})

test("escapeMarkup neutralises markup-shaped names", () => {
  const evil = '<img src="https://example.invalid/tracker"> & <b>x</b>'
  const escaped = Model.escapeMarkup(evil)
  assert.ok(!/[<>]/.test(escaped))
  assert.equal(escaped, '&lt;img src="https://example.invalid/tracker"&gt; &amp; &lt;b&gt;x&lt;/b&gt;')
})

test("isSecretsError recognises missing-password failures", () => {
  assert.ok(Model.isSecretsError("Error: Connection activation failed: Secrets were required, but not provided."))
  assert.ok(Model.isSecretsError("Error: Connection activation failed: No agents were available for this request."))
  assert.ok(!Model.isSecretsError("Error: Connection activation failed: The VPN service stopped unexpectedly."))
  assert.ok(!Model.isSecretsError(""))
})

test("every QML Text renders plain text", () => {
  for (const file of readdirSync(root).filter(f => f.endsWith(".qml"))) {
    const src = readFileSync(join(root, file), "utf8")
    const blocks = src.split(/\bText \{/).slice(1)
    blocks.forEach((block, i) => {
      const firstLines = block.split("\n").slice(0, 3).join("\n")
      assert.match(firstLines, /textFormat: Text\.PlainText/, `${file}: Text #${i + 1} lacks textFormat: Text.PlainText`)
    })
  }
})

test("translations match the English catalog", () => {
  const dir = join(root, "i18n")
  const en = JSON.parse(readFileSync(join(dir, "en.json"), "utf8"))
  const placeholders = s => (String(s).match(/%\d/g) || []).sort().join(",")
  for (const file of readdirSync(dir).filter(f => f.endsWith(".json") && f !== "en.json")) {
    const tr = JSON.parse(readFileSync(join(dir, file), "utf8"))
    assert.deepEqual(Object.keys(tr).sort(), Object.keys(en).sort(), `${file}: key set differs from en.json`)
    for (const key of Object.keys(en)) {
      assert.equal(placeholders(tr[key]), placeholders(en[key]), `${file}: placeholders differ for ${key}`)
    }
  }
})

test("every key used in QML exists in en.json", () => {
  const en = JSON.parse(readFileSync(join(root, "i18n", "en.json"), "utf8"))
  // Match every literal that looks like a catalog key, including ones chosen
  // inside a ternary such as strings.t(a ? "row.connect" : "row.disconnect").
  const prefixes = [...new Set(Object.keys(en).map(k => k.split(".")[0]))].join("|")
  const keyLiteral = new RegExp(`"((?:${prefixes})\\.[A-Za-z]+)"`, "g")
  for (const file of readdirSync(root).filter(f => f.endsWith(".qml"))) {
    const src = readFileSync(join(root, file), "utf8")
    for (const [, key] of src.matchAll(keyLiteral)) {
      assert.ok(key in en, `${file}: unknown translation key ${key}`)
    }
  }
})
