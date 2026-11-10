import Testing
import InsteonCLISupport
import InsteonCore
import InsteonLinking

/// The modem's role `--controller`, `--responder` or neither asks for.
struct LinkingRoleTests {

  @Test func linksADeviceByItsAddressAsControllerUnlessResponderIsAsked() {

    #expect(LinkingRole.controller.modemRole == .controller)
    #expect(LinkingRole.either.modemRole == .controller)
    #expect(LinkingRole.responder.modemRole == .responder)

  }

  @Test func letsTheSETButtonChooseOnlyWhenNoRoleIsAsked() {

    #expect(LinkingRole.controller.manualRole == .controller)
    #expect(LinkingRole.responder.manualRole == .responder)
    #expect(LinkingRole.either.manualRole == .either)

  }

}
