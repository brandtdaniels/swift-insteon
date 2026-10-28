# ``InsteonNetworking``

The HTTP abstraction the Insteon clients send requests through.

## Overview

The Insteon clients depend on ``HTTPClient`` instead of a particular HTTP stack, so you
choose how requests are sent. ``URLSessionHTTPClient`` is the default. Add behavior such as
authentication by wrapping a client in a decorator:

```swift
import InsteonNetworking

let client: any HTTPClient = BasicAuthenticationHTTPClient(
  URLSessionHTTPClient(),
  user: username,
  password: password
)
```

To use another HTTP stack, conform it to ``HTTPClient``:

```swift
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking  // URLRequest on Linux
#endif
import InsteonNetworking

struct MyHTTPClient: HTTPClient {

  func send(_ request: URLRequest) async throws -> HTTPResponse {
    // Send the request with your stack and return its status, headers and body.
  }

}
```

## Topics

### Sending requests

- ``HTTPClient``
- ``HTTPResponse``
- ``HTTPClientError``

### Clients

- ``URLSessionHTTPClient``
- ``BasicAuthenticationHTTPClient``
