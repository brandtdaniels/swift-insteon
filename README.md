# swift-insteon

Swift packages for working with [INSTEON](https://www.insteon.com) home automation devices.

| Library | Description |
| --- | --- |
| [InsteonMessage](Packages/InsteonMessage) | Build INSTEON messages and encode them for sending to a modem or hub |

## Requirements

- Swift 6.0 or later
- Any platform Swift supports. The libraries depend only on the Swift standard library.

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
    .product(name: "InsteonMessage", package: "swift-insteon")
  ]
)
```

## Usage

```swift
import InsteonMessage

let lamp = InsteonAddress("1A.2B.3C")!

let turnOn = StandardMessage(to: lamp, command: StandardDirectCommand.on(level: 0xFF))
turnOn.hexString  // "1A2B3C0F11FF"

var userData = UserData()
userData[1] = 0x01

let getConfiguration = ExtendedMessage(
  to: lamp,
  command: ExtendedDirectCommand.extendedGetSet,
  userData: userData
)
getConfiguration.hexString  // ends in "D1", the checksum i2cs devices require
```

Commands the typed catalogues don't cover can be sent as raw bytes with `Command(command1:command2:)`, or added by conforming your own type to `CommandConvertible`.

## Documentation

Every public API is documented with DocC. Build the documentation in Xcode with **Product → Build Documentation**.

## Development

```sh
swift build
swift test
```

Each library lives in `Packages/<Name>`, with its sources, tests and DocC catalog, and is built from the root `Package.swift`.
