import Flutter
import Darwin
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private var networkChannel: FlutterMethodChannel?
  private var csvResult: FlutterResult?
  private var csvTemporaryURL: URL?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NetMapNetworkPlugin")
    let channel = FlutterMethodChannel(name: "netmap/network", binaryMessenger: registrar.messenger())
    networkChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "network":
      do {
        result(try activeWifiNetwork().dictionary)
      } catch {
        result(FlutterError(code: "WIFI", message: error.localizedDescription, details: nil))
      }
    case "probe":
      guard let arguments = call.arguments as? [String: Any],
            let interface = arguments["id"] as? String,
            let ip = arguments["ip"] as? String else {
        result(FlutterError(code: "ARGS", message: "Missing network or IP address.", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let response = try self.probe(ip: ip, interface: interface)
          DispatchQueue.main.async { result(response) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "PROBE", message: error.localizedDescription, details: nil))
          }
        }
      }
    case "openDevice":
      guard let arguments = call.arguments as? [String: Any],
            let ip = arguments["ip"] as? String,
            Self.parseIPv4(ip) != nil,
            let url = URL(string: "https://\(ip)") else {
        result(FlutterError(code: "ARGS", message: "Invalid device IP address.", details: nil))
        return
      }
      UIApplication.shared.open(url, options: [:]) { opened in
        if opened {
          result(nil)
        } else {
          result(FlutterError(code: "BROWSER", message: "Could not open the device in a browser.", details: nil))
        }
      }
    case "saveCsv":
      saveCsv(call, result: result)
    case "acquireMdnsMulticastLock", "releaseMdnsMulticastLock":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private struct WifiNetwork {
    let ip: String
    let prefix: Int
    let address: in_addr
    let mask: UInt32

    var dictionary: [String: Any] {
      ["ip": ip, "prefix": prefix, "gateway": NSNull(), "id": "en0"]
    }
  }

  private func activeWifiNetwork() throws -> WifiNetwork {
    var firstAddress: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&firstAddress) == 0, let firstAddress else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                    userInfo: [NSLocalizedDescriptionKey: "Could not read the active Wi-Fi interface."])
    }
    defer { freeifaddrs(firstAddress) }

    var current = firstAddress
    while true {
      let interface = current.pointee
      if let name = interface.ifa_name,
         String(cString: name) == "en0",
         let rawAddress = interface.ifa_addr,
         Int32(rawAddress.pointee.sa_family) == AF_INET,
         let rawMask = interface.ifa_netmask,
         Int32(rawMask.pointee.sa_family) == AF_INET {
        let address = rawAddress.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
        let maskAddress = rawMask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
        let mask = UInt32(bigEndian: maskAddress.s_addr)
        var prefix = 0
        var sawZero = false
        for bit in stride(from: 31, through: 0, by: -1) {
          if (mask & (UInt32(1) << bit)) != 0 {
            if sawZero {
              throw NSError(domain: "NetMap", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "The Wi-Fi subnet mask is invalid."])
            }
            prefix += 1
          } else {
            sawZero = true
          }
        }
        return WifiNetwork(ip: Self.formatIPv4(address), prefix: prefix, address: address, mask: mask)
      }
      guard let next = interface.ifa_next else { break }
      current = next
    }
    throw NSError(domain: "NetMap", code: 2,
                  userInfo: [NSLocalizedDescriptionKey: "Connect to a Wi-Fi network before scanning."])
  }

  private func probe(ip: String, interface: String) throws -> [String: Any] {
    let network = try activeWifiNetwork()
    guard interface == "en0" else {
      throw NSError(domain: "NetMap", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "The Wi-Fi connection changed. Scan again."])
    }
    guard let target = Self.parseIPv4(ip) else {
      throw NSError(domain: "NetMap", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid device IP address."])
    }
    let address = UInt32(bigEndian: target.s_addr)
    let local = UInt32(bigEndian: network.address.s_addr)
    guard (address & network.mask) == (local & network.mask) else {
      throw NSError(domain: "NetMap", code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Address is outside the Wi-Fi subnet."])
    }

    let ports = [22, 80, 443, 445, 554, 631, 8008, 8080, 9100]
    var responsive = false
    var openPorts = [Int]()
    for port in ports {
      let outcome = try probe(ip: target, source: network.address, port: port)
      responsive = responsive || outcome.responded
      if outcome.open { openPorts.append(port) }
    }
    return ["reachable": responsive, "ports": openPorts]
  }

  private func probe(ip: in_addr, source: in_addr, port: Int) throws -> (responded: Bool, open: Bool) {
    let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    guard descriptor >= 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                    userInfo: [NSLocalizedDescriptionKey: "Could not create a network probe socket."])
    }
    defer { Darwin.close(descriptor) }

    guard Darwin.fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                    userInfo: [NSLocalizedDescriptionKey: "Could not configure a network probe socket."])
    }

    var localAddress = sockaddr_in()
    localAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    localAddress.sin_family = sa_family_t(AF_INET)
    localAddress.sin_addr = source
    let bindResult = withUnsafePointer(to: &localAddress) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bindResult == 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                    userInfo: [NSLocalizedDescriptionKey: "Could not bind a network probe to Wi-Fi."])
    }

    var remoteAddress = sockaddr_in()
    remoteAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    remoteAddress.sin_family = sa_family_t(AF_INET)
    remoteAddress.sin_port = in_port_t(port).bigEndian
    remoteAddress.sin_addr = ip
    let connectResult = withUnsafePointer(to: &remoteAddress) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    if connectResult == 0 { return (true, true) }
    if errno == ECONNREFUSED { return (true, false) }
    if errno == EACCES || errno == EPERM {
      throw NSError(domain: "NetMap", code: Int(errno),
                    userInfo: [NSLocalizedDescriptionKey: "Allow NetMap to access the local network in iOS Settings, then scan again."])
    }
    guard errno == EINPROGRESS else { return (false, false) }

    var event = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
    guard Darwin.poll(&event, 1, 350) > 0 else { return (false, false) }
    var socketError: Int32 = 0
    var errorLength = socklen_t(MemoryLayout<Int32>.size)
    guard Darwin.getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &socketError, &errorLength) == 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                    userInfo: [NSLocalizedDescriptionKey: "Could not read the network probe result."])
    }
    if socketError == EACCES || socketError == EPERM {
      throw NSError(domain: "NetMap", code: Int(socketError),
                    userInfo: [NSLocalizedDescriptionKey: "Allow NetMap to access the local network in iOS Settings, then scan again."])
    }
    return (socketError == 0 || socketError == ECONNREFUSED, socketError == 0)
  }

  private static func parseIPv4(_ value: String) -> in_addr? {
    var address = in_addr()
    let parsed = value.withCString { inet_pton(AF_INET, $0, &address) }
    return parsed == 1 ? address : nil
  }

  private static func formatIPv4(_ address: in_addr) -> String {
    let value = UInt32(bigEndian: address.s_addr)
    return "\(value >> 24).\(value >> 16 & 255).\(value >> 8 & 255).\(value & 255)"
  }

  private func saveCsv(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard csvResult == nil else {
      result(FlutterError(code: "BUSY", message: "A save dialog is already open.", details: nil))
      return
    }
    guard let arguments = call.arguments as? [String: Any],
          let name = arguments["name"] as? String,
          let contents = arguments["contents"] as? String else {
      result(FlutterError(code: "ARGS", message: "Missing CSV file name or contents.", details: nil))
      return
    }
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      URL(fileURLWithPath: name).lastPathComponent
    )
    do {
      try Data(contents.utf8).write(to: fileURL, options: .atomic)
    } catch {
      result(FlutterError(code: "SAVE", message: "Could not prepare the CSV file for export.", details: nil))
      return
    }
    guard let presenter = topViewController() else {
      try? FileManager.default.removeItem(at: fileURL)
      result(FlutterError(code: "SAVE", message: "Could not open the file picker.", details: nil))
      return
    }
    let picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
    picker.delegate = self
    csvResult = result
    csvTemporaryURL = fileURL
    presenter.present(picker, animated: true)
  }

  private func topViewController() -> UIViewController? {
    let root = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)?
      .rootViewController
    var current = root
    while let presented = current?.presentedViewController {
      current = presented
    }
    return current
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    csvResult?(urls.isEmpty ? nil : "selected file")
    finishCsvExport()
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    csvResult?(nil)
    finishCsvExport()
  }

  private func finishCsvExport() {
    csvResult = nil
    if let url = csvTemporaryURL {
      try? FileManager.default.removeItem(at: url)
    }
    csvTemporaryURL = nil
  }
}
