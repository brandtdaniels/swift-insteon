# ``InsteonModem``

Talk to an INSTEON modem, such as a PowerLinc Modem on a USB or serial port.

## Overview

A PowerLinc Modem (2413U by USB, 2413S by serial cable), or another modem from
<doc:SupportedModems>, connects your computer to the INSTEON network. ``Modem`` speaks the
modem's serial protocol over any ``ModemConnection``:
it sends commands one at a time, waits for the modem to accept each one, retries when the
modem is busy, and publishes everything the modem sends back.

```swift
import InsteonModem
import InsteonProtocol

try await Modem.withConnection(SerialPort(path: "/dev/ttyUSB0")) { modem in
  let replies = await modem.replies()

  let lamp = InsteonAddress(0xAA, 0xBB, 0xCC)
  try await modem.send(.sendStandardMessage(
    StandardMessage(to: lamp, command: StandardDirectCommand.on(level: 0xFF))
  ))

  for await reply in replies {
    if case let .messageReceived(message) = reply, message.sender == lamp {
      // The lamp acknowledged the command.
      break
    }
  }
}
```

``Modem/withConnection(_:retryPolicy:clock:isolation:_:)`` reads what the modem sends while
the closure runs, and closes the modem when it returns, so the modem's lifetime follows the
structure of your code. To keep a modem open for the life of an app, create a ``Modem`` and
call ``Modem/run()`` in a task that lasts as long as the app: canceling that task closes the
modem.

``Modem`` conforms to `SerialCommandSender`, so code written against that protocol works with
any modem connection.

### Connections

``SerialPort`` connects to a modem on a serial port on macOS and Linux, and `HubConnection`
from InsteonHubClient connects to the modem inside an INSTEON Hub. To reach a modem another
way, such as through a network-attached serial adapter, conform a type to ``ModemConnection``.

## Topics

### Essentials

- <doc:SupportedModems>

### Modems

- ``Modem``
- ``ModemError``
- ``PowerLincController``
- ``PowerLincControllerError``

### Connections

- ``ModemConnection``
- ``SerialPort``
- ``SerialPortError``
