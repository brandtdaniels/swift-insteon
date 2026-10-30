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

### Credentials and redirects

A request with credentials is never sent on to another address. ``URLSessionHTTPClient``
doesn't follow a redirect for a request with an `Authorization` header, such as one
``BasicAuthenticationHTTPClient`` sends, and throws ``HTTPClientError/redirectRefused``
instead. An Insteon Hub never redirects its own requests, so a redirect means the request
reached something other than the Hub. Requests without credentials follow redirects, except
that an HTTPS request that ends at an address that isn't HTTPS throws
``HTTPClientError/insecureRedirect``.

### Other HTTP stacks

To use another HTTP stack, conform it to ``HTTPClient``. If it sends requests with
credentials, it must refuse redirects for them the same way:

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
