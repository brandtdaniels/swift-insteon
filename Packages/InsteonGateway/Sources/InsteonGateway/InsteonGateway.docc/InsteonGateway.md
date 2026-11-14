# ``InsteonGateway``

An authenticated Swift request boundary and device controller for a home service.

## Overview

Create a ``NetworkGatewayController`` from an open InsteonCore session's network. Pass it to
``Gateway``, then adapt incoming requests to ``GatewayRequest`` and write each
``GatewayResponse``. The optional server package in the repository provides an HTTP adapter.

The gateway serves HTML and a versioned device API without a server framework dependency.
Reads use cached descriptions. Controls are explicit, authenticated operations that use
InsteonCore's device capabilities and catalog restrictions. Only one controller operation is
active at a time; another request receives a busy response rather than entering a queue.

The hosting application must provide an encrypted private connection or HTTPS. The gateway's
password is independent of the Hub's credentials, which stay on the home service.

## Topics

### Requests and authentication

- ``Gateway``
- ``GatewayRequest``
- ``GatewayResponse``
- ``GatewayConfigurationError``

### Devices and controls

- ``GatewayControlling``
- ``NetworkGatewayController``
- ``GatewayDeviceList``
- ``GatewayDevice``
- ``GatewayCommand``
- ``GatewayCommandResult``
- ``GatewayControlError``
- ``GatewayEvent``
