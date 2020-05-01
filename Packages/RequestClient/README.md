# RequestClient

`RequestClientProtocol` is protocol for sending requests over the network. This package includes an implementation that wraps `URLSession` called `URLSessionRequestClient`. The protocol allows the creation of a mock when this protocol is a dependency of a more specific client. The thin wrapper removes the requirement for testing as `URLSession` is provided by Apple.
