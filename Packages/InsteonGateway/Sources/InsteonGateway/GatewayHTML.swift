import Foundation
import InsteonCore
import InsteonProtocol

/// Server-generated HTML; it needs no client scripts or external assets.
enum GatewayHTML {
  static func page(devices: [GatewayDevice], formKey: String) -> String {
    let cards = devices.map { card($0, formKey: formKey) }.joined(separator: "\n")
    let empty = devices.isEmpty ? "<p>No devices are known. Read the modem's links at startup or import a saved network snapshot.</p>" : ""
    return """
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Insteon home</title><style>
    :root{color-scheme:light dark;font-family:system-ui,sans-serif}body{max-width:58rem;margin:auto;padding:1.5rem;background:Canvas;color:CanvasText}
    h1{margin-bottom:.4rem}header{margin-bottom:2rem}.devices{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,22rem),1fr));gap:1rem}
    article{border:1px solid GrayText;border-radius:.8rem;padding:1.2rem}h2{margin-top:0;font-size:1.15rem}small{display:block;margin:.6rem 0;color:GrayText}
    form{display:inline-flex;align-items:center;gap:.5rem;flex-wrap:wrap;margin:.3rem .3rem .3rem 0}button,input{font:inherit;min-height:2.8rem;border-radius:.4rem}
    button{padding:.4rem 1rem;cursor:pointer}input[type=number]{width:5rem;padding:0 .5rem}a{color:LinkText}footer{margin-top:2rem}
    </style></head><body><header><h1>Insteon home</h1><p>Your home gateway</p>
    <p>Cached values can be stale. Use Read status to ask a device. An acknowledged control is not a verified status reading.</p><a href="/">Refresh page</a></header>
    \(empty)<main class="devices">\(cards)</main><footer><small>Local or encrypted private access. This gateway does not use the Hub's cloud connection.</small></footer></body></html>
    """
  }

  private static func card(_ device: GatewayDevice, formKey: String) -> String {
    let path = "/devices/" + escape(device.address)
    let hidden = "<input type=\"hidden\" name=\"formKey\" value=\"" + escape(formKey) + "\">"
    func form(_ action: String, _ label: String, extra: String = "") -> String {
      "<form method=\"post\" action=\"" + path + "\">" + hidden + "<input type=\"hidden\" name=\"action\" value=\"" + action + "\">" + extra + "<button type=\"submit\">" + label + "</button></form>"
    }
    var controls = form("identify", "Identify") + form("status", "Read status")
    if device.canTurnOnAndOff {
      let level = device.canDim ? "<label>Level % <input type=\"number\" name=\"levelPercent\" min=\"0\" max=\"100\" step=\"1\" placeholder=\"100\"></label>" : ""
      controls += form("on", "On", extra: level) + form("off", "Off")
    }
    let value: String
    if let byte = device.value {
      value = device.canDim ? String(LightLevel.percent(level: byte)) + "%" : "value " + String(byte)
    } else {
      value = "unknown"
    }
    let answered = device.lastAnsweredAt.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown"
    return """
    <article><h2>\(escape(device.productName ?? "Unidentified device"))</h2><code>\(escape(device.address))</code>
    <p>Cached: \(escape(value))</p><small>Last answered: \(escape(answered))</small>\(controls)</article>
    """
  }

  private static func escape(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
  }
}
