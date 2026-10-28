# InsteonLinking

Link Insteon devices to each other and to the modem: by writing the records of each link into the devices' ALL-Link databases, remotely by putting a device into linking mode, or manually with its SET button.

## Types

- `AllLinkGroup`: a controller's ALL-Link group and its responders, each with its link data, such as a dimmer's on-level and ramp rate
- `LinkEndpoint`: one end of a link, the modem or a device
- `Linker`: writes a group's controller and responder records, reusing free records and checking each write; links a device to the modem remotely (i2 and i2cs) or with its SET button (every engine)
- `Unlinker`: deletes a group's records, or unlinks a device from the modem remotely or with its SET button
- `ModemRole`: whether the modem controls a device or responds to it
- `AllLinkGroupReader`: reads the groups of the modem and a list of devices back from their databases, with any half links and devices it couldn't read
- `AllLinkDatabaseCache`: keeps the modem's and devices' ALL-Link databases, reading a device's again only when its database delta changes
- `LinkingModem`: what the linker needs from a modem; `Modem` from InsteonModem conforms

Devices with an i2 or i2cs engine accept database writes; an i2cs device accepts them only once it's linked to the modem.

See the DocC catalog in `Sources/InsteonLinking/InsteonLinking.docc` for the full documentation.
