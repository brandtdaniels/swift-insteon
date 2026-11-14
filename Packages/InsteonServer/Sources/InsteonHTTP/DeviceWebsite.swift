import Hummingbird
import InsteonCore
import InsteonService

/// Browser presentation needs only queries and commands, not an event source or modem type.
actor DeviceWebsite<Service: DeviceQuerying & DeviceCommanding> {
  let service: Service
  private let forms = BrowserFormProtection()
  private var cachedDevices: [ServiceDevice] = []

  init(service: Service) { self.service = service }

  func index(_ request: Request) async throws -> Response {
    let notice = request.uri.queryParameters["notice"] == "persistence-failed" ? "The device operation completed, but its snapshot could not be saved. Do not repeat the control just to retry storage." : nil
    var failure = request.uri.queryParameters["error"].flatMap { BrowserCommandFailure(rawValue: String($0)) }
    let failedAddress = request.uri.queryParameters["device"].flatMap { InsteonAddress(String($0))?.description }
    do {
      cachedDevices = try await service.devices()
    } catch ServiceControlError.busy {
      // Retain the last rendered list while another caller owns the service. Following
      // a command redirect must not replace the controls with a second busy error page.
      failure = failure ?? .busy
    }
    let page = HTMLRenderer.page(devices: cachedDevices, formKey: forms.key, notice: notice, error: failure?.message, failedAddress: failedAddress)
    return Response(status: .ok, headers: [.contentType: "text/html; charset=utf-8"], body: .init(byteBuffer: ByteBuffer(string: page)))
  }

  func command(_ request: Request, address: String?) async throws -> Response {
    let command: ServiceCommand
    do {
      let input = try await forms.command(request)
      command = try input.serviceCommand(address: address)
    } catch HTTPInputError.invalidFormKey {
      return rejection(.expiredForm, address: address)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      return rejection(.invalidForm, address: address)
    }
    do {
      let receipt = try await service.execute(command)
      return Response(status: .seeOther, headers: [.location: receipt.persistence == .failed ? "/?notice=persistence-failed" : "/"])
    } catch {
      let failure = BrowserCommandFailure(error, action: command.action)
      return rejection(failure, address: command.address.description)
    }
  }

  private func rejection(_ failure: BrowserCommandFailure, address: String?) -> Response {
    let address = address.flatMap { InsteonAddress($0)?.description }
    let target = address.map { "&device=" + $0 + "#device-" + $0 } ?? ""
    return Response(status: .seeOther, headers: [.location: "/?error=" + failure.rawValue + target])
  }
}

/// Only fixed presentation codes cross the redirect; provider diagnostics stay private.
private enum BrowserCommandFailure: String {
  case busy, unknownDevice, invalidLevel, unsupportedControl, statusFailed, identifyFailed, controlFailed, expiredForm, invalidForm

  init(_ error: any Error, action: ServiceCommand.Action) {
    switch error {
    case ServiceControlError.busy: self = .busy
    case ServiceControlError.unknownDevice: self = .unknownDevice
    case ServiceControlError.invalidLevel: self = .invalidLevel
    case ServiceControlError.unsupportedControl: self = .unsupportedControl
    default:
      switch action {
      case .status: self = .statusFailed
      case .identify: self = .identifyFailed
      case .on, .off: self = .controlFailed
      }
    }
  }

  var message: String {
    switch self {
    case .busy: "The service is busy. Nothing was queued. Wait for the other operation to finish, then try again."
    case .unknownDevice: "This device is no longer known to the service. Refresh the page."
    case .invalidLevel: "This device or action does not accept that percentage. Use a supported level from 0 through 100."
    case .unsupportedControl: "This device does not support that control."
    case .statusFailed: "Could not read status. The device may be unreachable or may not support this request. Try Identify or check its connection."
    case .identifyFailed: "Could not identify this device. Check its connection before trying again."
    case .controlFailed: "The control failed and its hardware outcome may be unknown. Read status before deciding whether to repeat it."
    case .expiredForm: "This form expired. No command was sent. Use the controls on this refreshed page to try again."
    case .invalidForm: "The form could not be read. No command was sent. Check the values and use the controls on this refreshed page to try again."
    }
  }
}
