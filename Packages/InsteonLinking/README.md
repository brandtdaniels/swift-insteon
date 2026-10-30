# InsteonLinking

Link Insteon devices to each other and to the modem: by writing the records of each link into the devices' ALL-Link databases, remotely by putting a device into linking mode, or manually with its SET button.

## Types

- `AllLinkGroup`: a controller's ALL-Link group and its responders, each with its link data, such as a dimmer's on-level and ramp rate
- `LinkEndpoint`: one end of a link, the modem or a device
- `Linker`: writes a group's controller and responder records, reusing free records and checking each write; links a device to the modem remotely (i2 and i2CS) or with its SET button (every engine)
- `Unlinker`: deletes a group's records, or unlinks a device from the modem remotely or with its SET button; `unlinkAllRemotely` removes every link between the modem and a device, in both directions, without its SET button
- `linkManually(as:group:device:timeout:ready:)` and `unlinkManually(as:group:device:timeout:ready:)`: manual linking that calls back once the modem is ready, with the modem as controller, responder or either
- `LinkMismatch`: a reported link that isn't the one asked for, from another device, or made where one was to be removed, or the reverse
- `ResponderState` and `prepareResponder`: turn a device on, or to a level, before it links as a responder, so it memorizes that on-level
- `firstReply(within:clock:after:matching:)`: listens to the modem, sends, and waits for the first matching reply or a timeout
- `ModemRole`: whether the modem controls a device or responds to it
- `AllLinkGroupReader`: reads the groups of the modem and a list of devices back from their databases, with any half links and devices it couldn't read
- `AllLinkDatabaseCache`: keeps the modem's and devices' ALL-Link databases, reading a device's again only when its database delta changes; `modemLinks(of:)` gives the modem's records for one device
- `LinkingModem`: what the linker needs from a modem; `Modem` from InsteonModem conforms

Devices with an i2 or i2CS engine accept database writes; an i2CS device accepts them only once it's linked to the modem.

See the DocC catalog in `Sources/InsteonLinking/InsteonLinking.docc` for the full documentation.
