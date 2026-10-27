# Message Format

How an INSTEON message is laid out, byte by byte.

## Overview

A message on the INSTEON network starts with the sender's and recipient's addresses. When you
send through a modem, the modem fills in its own address as the sender, so the messages in
this package start with the destination.

### Standard-length messages

Six bytes:

| Bytes | Content |
| --- | --- |
| 1–3 | Destination address, most significant byte first |
| 4 | Flags |
| 5 | cmd1, which selects the operation |
| 6 | cmd2, which carries its argument |

### Extended-length messages

Twenty bytes: the six above followed by 14 bytes of user data, D1 through D14. Extended
messages carry configuration and database records too large for cmd2.

### Flags

| Bits | Field | Values |
| --- | --- | --- |
| 7–5 | Message type | Direct, broadcast, ALL-Link broadcast, ALL-Link cleanup, and acknowledgements of each |
| 4 | Extended | `1` for extended-length messages |
| 3–2 | Hops left | Retransmissions remaining, 0–3 |
| 1–0 | Max hops | Retransmissions allowed, 0–3 |

INSTEON devices repeat messages they hear to extend range. Each repeat decrements the hops
left; a message is not repeated once it reaches zero, or by the device it's addressed to. A
new message starts with hops left equal to max hops.

The protocol's convention is three max hops for broadcasts and ALL-Link broadcasts, and one
for direct and ALL-Link cleanup messages, which the sending device raises on each retry up to
three. Hosts sending through a modem commonly use three for every message, as this package
does by default: `0x0F` for standard direct messages and `0x1F` for extended ones.

### Message types and addresses

What the destination and cmd2 carry depends on the message type:

| Type | Destination | cmd2 |
| --- | --- | --- |
| Direct | The receiving device | The command's argument |
| Broadcast | The sender's device category and subcategory, then `0xFF` or its firmware version | Depends on the command |
| ALL-Link broadcast | `00.00.<group>` | `0x00` |
| ALL-Link cleanup | A device in the group | The group |

Direct and broadcast messages can be standard or extended. ALL-Link broadcasts and cleanups,
and the acknowledgements of every type, are standard only.

### Acknowledgements

A device acknowledges a direct or ALL-Link cleanup message with an ACK of the same type. A
direct ACK can carry data in cmd2, such as the level in reply to a status request. A NAK
carries the reason in cmd2; read it with ``NAKReason``.

### Engines

Each device runs an INSTEON engine, which reports through
``StandardDirectCommand/getEngineVersion``. Every engine supports the base commands; the i2
engine adds more, and the i2cs engine also requires checksums on extended messages. A command's
`minimumEngine` gives the engine from which every device supports it. See ``InsteonEngine``.

### Integrity of extended messages

The INSTEON radio layer checks each message, but i2cs devices also verify an extended message's
user data before acting on it:

- Most commands use a one-byte checksum in D14 (``ChecksumIntegrity``): the two's complement
  of the sum of cmd1, cmd2 and D1–D13.
- Some devices use a two-byte CRC in D13–D14 for certain commands (``CRCIntegrity``).

``ExtendedMessage`` applies the checksum by default. Devices with i1 and i2 engines ignore it,
so it is safe to send to them.
