# InsteonGateway

A reusable Swift gateway for one Insteon network, independent of an HTTP server framework.

`NetworkGatewayController` holds a `DeviceNetwork` from a persistent `ModemSession`. It uses the
same `Device` operations as the CLI, retaining the catalog's controls and restrictions.
`Gateway` authenticates requests, validates commands, renders HTML and returns versioned JSON.
The [optional server](../InsteonServer) adapts it to HTTP on macOS and Linux.

## Behavior

- Given no valid server credential, a request is refused before reading devices or sending
  commands.
- Given a page or device list request, only cached information is read. A page load sends no
  command to hardware.
- Given an explicit, authenticated control request, a known device's main group is controlled
  through InsteonCore. Percentages are accepted only for On, from 0 through 100, on a group
  that dims.
- Given another controller operation in progress, a request receives 409. It isn't queued.
- Given a failed operation, the response says its hardware outcome may be unknown. A control
  isn't retried automatically.
- Given a browser form without its per-process form key, the request is refused. Successful
  forms redirect to GET so refreshing the page doesn't repeat a command.

## Types

- `GatewayControlling`: the device list and command operations an adapter supplies.
- `NetworkGatewayController`: the InsteonCore adapter; lists known devices, executes controls,
  saves network snapshots and exposes named device events.
- `Gateway`: the authenticated website and HTTP request boundary, without a network listener.
- `GatewayRequest`, `GatewayResponse`: requests and responses represented with Foundation
  values.
- `GatewayDeviceList`, `GatewayDevice`, `GatewayCommandResult`, `GatewayEvent`: versioned
  response and event values a Swift client can decode. JSON dates use ISO 8601.
- `GatewayCommand`: identification, status, On and Off operations on a device's main group.

The device list includes known identities, cached device state and active modem links. Devices
without an identity have no switching controls until explicitly identified. Cached bytes may
come from acknowledged controls; they aren't proof that a status was read. `lastAnsweredAt`
records when a device answered a command, not when a passive event was heard. Event consumers
must request status explicitly when they need a confirmed reading.

The optional snapshot store is written after successful commands and at service startup and
shutdown. Live events aren't kept as history. Identity changes heard while otherwise idle
remain in memory until a snapshot is saved. Use a dedicated store and one controller per modem.

## Authentication and transport

The website and JSON API use HTTP Basic authentication with the user name `insteon` and a
separate, randomly generated server password of 32 through 1024 bytes. Hub credentials are
never sent to remote clients. Passwords and request bodies must not be logged.

The gateway doesn't encrypt HTTP. Serve it on loopback or over an encrypted private VPN
connection, or supply HTTPS in a hosting application. Binding to a private address alone
doesn't encrypt traffic. Do not expose the server or Hub through router port forwarding.
Browser pages need no JavaScript or external resources. JSON commands require the custom
`X-Insteon-Request: 1` header and `application/json`, so a cross-origin HTML form cannot submit
an API command. No cross-origin access is enabled.

Tests use a recording controller and an in-memory modem. Hardware behavior must be verified on
the intended Hub or modem before deployment.
