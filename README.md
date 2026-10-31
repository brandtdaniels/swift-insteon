# swift-insteon

[![CI](https://github.com/brandtdaniels/swift-insteon/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/brandtdaniels/swift-insteon/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Swift packages for working with [Insteon](https://www.insteon.com) home automation devices.

| Library | Description |
| --- | --- |
| [InsteonCore](Packages/InsteonCore) | Keep track of the devices on a network, each with what the Insteon device catalog says about it: the library an app or a command builds on |
| [InsteonProtocol](Packages/InsteonProtocol) | The Insteon protocol as value types: messages for devices, the serial commands that carry them through a modem, and the IBIOS commands of a PowerLinc Controller |
| [InsteonModem](Packages/InsteonModem) | Control Insteon devices through a PowerLinc Modem or USB Adapter on a USB or serial port, or a PowerLinc Controller 2414S |
| [InsteonLinking](Packages/InsteonLinking) | Link devices to each other and to the modem: by writing their ALL-Link databases, remotely, or with their SET buttons |
| [InsteonHubClient](Packages/InsteonHubClient) | Control Insteon devices through an Insteon Hub on your local network, by driving its built-in modem with InsteonModem |
| [InsteonHubDiscovery](Packages/InsteonHubDiscovery) | Find Insteon Hubs on your local network, by asking the network itself or Insteon Connect |
| [InsteonHubPro](Packages/InsteonHubPro) | Add Insteon devices to a Hub Pro and read its settings and update its software through its local interface |
| [InsteonScheduling](Packages/InsteonScheduling) | Work out when schedules run, at clock times or around sunrise and sunset, in a home's time zone through daylight saving changes |
| [InsteonDeviceCatalog](Packages/InsteonDeviceCatalog) | Look a device up in the [Insteon device catalog](https://github.com/brandtdaniels/insteon-device-catalog) by the category, subcategory and firmware version it reports, to find what it is and can do, such as its groups, what its group commands mean and its heartbeat interval, and read its messages as named events |
| [InsteonNotifications](Packages/InsteonNotifications) | Let people know when their devices do something they care about, such as a leak sensor turning wet, a door opening or a sensor going quiet |
| [InsteonNetworking](Packages/InsteonNetworking) | The `HTTPClient` abstraction the Insteon clients send requests through |

The package also has a command, [`insteon`](Packages/InsteonCLI), for driving a Hub or modem, and its devices, from a terminal: finding Hubs, reading ALL-Link databases, linking devices by their addresses or SET buttons, sending commands and watching events.

The [Supported Modems](Packages/InsteonModem/Sources/InsteonModem/InsteonModem.docc/SupportedModems.md) article lists every modem, Hub and controller, and how well each is supported.

## Requirements

- Swift 6.3 or later
- macOS 13, iOS 16, tvOS 16, watchOS 9, visionOS 1 or later, or Linux
- `SerialPort`, in InsteonModem, is available on macOS and Linux
- InsteonProtocol depends only on the Swift standard library; the other libraries use Foundation
- InsteonDeviceCatalog uses Apple's [swift-crypto](https://github.com/apple/swift-crypto), which is CryptoKit on Apple platforms, to check downloaded catalogs

## Installation

Add the package to your `Package.swift`:

```swift
.package(url: "https://github.com/brandtdaniels/swift-insteon", branch: "main")
```

Then add the libraries you need to your target:

```swift
.target(
  name: "MyApp",
  dependencies: [
    .product(name: "InsteonModem", package: "swift-insteon"),
    .product(name: "InsteonProtocol", package: "swift-insteon")
  ]
)
```

## Usage

### Talking to a modem

`Modem.withConnection` opens a modem, reads what it sends while your closure uses it, and closes it when the closure returns:

```swift
import InsteonModem
import InsteonProtocol

let lamp = InsteonAddress("1A.2B.3C")!

try await Modem.withConnection(SerialPort(path: "/dev/ttyUSB0")) { modem in
  // Returns once the lamp acknowledges the command, and throws if it rejects it.
  try await modem.request(StandardMessage(to: lamp, command: StandardDirectCommand.on(level: 0xFF)))
}
```

An Insteon Hub works the same way through its built-in modem:

```swift
import InsteonHubClient

let hub = Hub(endpoint: HubEndpoint(host: "192.168.1.20"), user: username, password: password)

try await Modem.withConnection(HubConnection(hub: hub)) { modem in
  try await modem.send(.getModemInfo)
}
```

The Hub's user name and password are printed on it. Keep them out of source code, for example in the keychain.

### Building messages

```swift
import InsteonProtocol

let lamp = InsteonAddress("1A.2B.3C")!

let turnOn = StandardMessage(to: lamp, command: StandardDirectCommand.on(level: 0xFF))
turnOn.hexString  // "1A2B3C0F11FF"

var userData = UserData()
userData[1] = 0x01

let getConfiguration = ExtendedMessage(
  to: lamp,
  command: ExtendedDirectCommand.getSet(),
  userData: userData
)
getConfiguration.hexString  // ends in "D1", the checksum i2CS devices require
```

Commands the typed catalogs don't cover can be sent as raw bytes with `Command(command1:command2:)`, or added by conforming your own type to `CommandConvertible`.

### From the terminal

Put the Hub's user name and password in `~/.config/insteon/env` (or `$XDG_CONFIG_HOME/insteon/env`), and make it readable only by you with `chmod 600 ~/.config/insteon/env`:

```sh
INSTEON_HUB_USERNAME=your-hub-user-name
INSTEON_HUB_PASSWORD=your-hub-password
```

Then:

```sh
swift run insteon --hub 192.168.1.20 info
swift run insteon --hub 192.168.1.20 link
swift run insteon --hub 192.168.1.20 device 1A.2B.3C on 50%
swift run insteon --help
```

The command reads the credentials only from the environment or that file, never from its arguments or from a file in the current directory. It sends them only to a private IPv4 address, in `10.0.0.0/8`, `172.16.0.0/12` or `192.168.0.0/16`, given with `--hub` or `INSTEON_HUB_HOST`, and refuses a host name or any other address before sending anything. Requests go to the Hub directly, never through a proxy. `Scripts/install-insteon.sh [PREFIX]` installs it, with the Insteon device catalog it names products from, into `PREFIX/bin`, `~/.local/bin` by default. See [InsteonCLI](Packages/InsteonCLI) for every command.

## Documentation

Every public API is documented with DocC. Build the documentation in Xcode with **Product → Build Documentation**.

## Development

```sh
swift build
swift test
```

Each library lives in `Packages/<Name>`, with its sources, tests and DocC catalog, and is built from the root `Package.swift`. `Scripts/build-docs.sh` builds every library's documentation and fails on any warning.

[CONVENTIONS.md](CONVENTIONS.md) says how the docs name Insteon's products, commands and documents, and `python3 Scripts/check-terms.py` checks the forms it rules out.

## License

The code in this repository is available under the MIT License. See [LICENSE](LICENSE).

Insteon is a trademark of its owner. This project is an independent implementation of the publicly documented Insteon protocol. It is not affiliated with, endorsed by or sponsored by Insteon or its owner, and the license covers only this project's code.
