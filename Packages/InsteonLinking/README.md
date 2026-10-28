# InsteonLinking

Link INSTEON devices to each other and to the modem, by writing the records of each link into the devices' ALL-Link databases.

## Types

- `AllLinkGroup`: a controller's ALL-Link group and its responders, each with its link data, such as a dimmer's on-level and ramp rate
- `LinkEndpoint`: one end of a link, the modem or a device
- `Linker`: writes a group's controller and responder records, reusing free records and checking each write
- `Unlinker`: deletes a group's records
- `LinkingModem`: what the linker needs from a modem; `Modem` from InsteonModem conforms

Devices with an i2 or i2cs engine accept database writes; an i2cs device accepts them only once it's linked to the modem.

See the DocC catalog in `Sources/InsteonLinking/InsteonLinking.docc` for the full documentation.
