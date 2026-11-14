import Hummingbird
import HTTPTypes
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
    let fragment = request.headers[HTTPField.Name("X-Insteon-Fragment")!] == "device"
    let command: ServiceCommand
    do {
      let input = try await forms.command(request)
      command = try input.serviceCommand(address: address)
    } catch HTTPInputError.invalidFormKey {
      return await rejection(.expiredForm, address: address, fragment: fragment)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      return await rejection(.invalidForm, address: address, fragment: fragment)
    }
    do {
      let receipt = try await service.execute(command)
      if fragment {
        let notice = receipt.persistence == .failed ? "The device operation completed, but its snapshot could not be saved. Do not repeat the control just to retry storage." : nil
        return await cardResponse(address: command.address, notice: notice)
      }
      let address = command.address.description
      let location = receipt.persistence == .failed ? "/?notice=persistence-failed&device=" + address : "/"
      return Response(status: .seeOther, headers: [.location: location + "#device-" + address])
    } catch {
      let failure = BrowserCommandFailure(error, action: command.action)
      return await rejection(failure, address: command.address.description, fragment: fragment)
    }
  }

  private func rejection(_ failure: BrowserCommandFailure, address: String?, fragment: Bool) async -> Response {
    if fragment, let address = address.flatMap(InsteonAddress.init) {
      return await cardResponse(address: address, failure: failure)
    }
    let address = address.flatMap { InsteonAddress($0)?.description }
    let target = address.map { "&device=" + $0 + "#device-" + $0 } ?? ""
    return Response(status: .seeOther, headers: [.location: "/?error=" + failure.rawValue + target])
  }

  private func cardResponse(address: InsteonAddress, failure: BrowserCommandFailure? = nil, notice: String? = nil) async -> Response {
    var notice = notice
    do {
      cachedDevices = try await service.devices()
    } catch {
      let stale = "Showing previously displayed device information; refresh is temporarily unavailable."
      notice = notice.map { $0 + " " + stale } ?? stale
    }
    guard let device = cachedDevices.first(where: { $0.address == address }) else {
      return Response(status: .notFound, headers: [.contentType: "text/plain; charset=utf-8"], body: .init(byteBuffer: ByteBuffer(string: "The device is unavailable. Refresh the page.")))
    }
    let html = HTMLRenderer.card(device, formKey: forms.key, error: failure?.message, notice: notice)
    return Response(status: failure?.status ?? .ok, headers: [.contentType: "text/html; charset=utf-8"], body: .init(byteBuffer: ByteBuffer(string: html)))
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

  var status: HTTPResponse.Status {
    switch self {
    case .busy: .conflict
    case .unknownDevice: .notFound
    case .invalidLevel, .invalidForm: .badRequest
    case .unsupportedControl: .unprocessableContent
    case .expiredForm: .forbidden
    case .statusFailed, .identifyFailed, .controlFailed: .badGateway
    }
  }
}
