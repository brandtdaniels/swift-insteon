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
left; a message is not repeated once it reaches zero. Messages are normally sent with three
hops: `0x0F` for standard direct messages and `0x1F` for extended ones.

### Integrity of extended messages

The INSTEON radio layer checks each message, but i2cs devices also verify an extended message's
user data before acting on it:

- Most commands use a one-byte checksum in D14 (``ChecksumIntegrity``): the two's complement
  of the sum of cmd1, cmd2 and D1–D13.
- Some newer devices use a two-byte CRC in D13–D14 for certain commands (``CRCIntegrity``).

``ExtendedMessage`` applies the checksum by default. Older devices ignore it, so it is safe to
send to them.
