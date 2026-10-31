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
reached something other than the Hub.

### The local network

A Hub's interface is plain HTTP, so a proxy that carried its requests would read the Hub's
user name and password. ``URLSessionHTTPClient/localNetwork(maximumResponseSize:resourceTimeout:)``
makes the client for devices on the local network, with a session of its own:

- It sends each request to the device directly. On Apple platforms its configuration turns
  every proxy off. On Linux, swift-corelibs-foundation ignores that setting and libcurl uses
  the proxy the environment names, in `http_proxy`, `HTTP_PROXY`, `all_proxy` or
  `ALL_PROXY`, so the client refuses a request a proxy would carry with
  ``HTTPClientError/proxyConfigured``. Naming the device's address in `no_proxy` sends it
  directly.
- It keeps no cookies, credentials or cache, and follows no redirects.
- It reads at most ``URLSessionHTTPClient/localNetworkMaximumResponseSize`` bytes of an
  answer, and throws ``HTTPClientError/responseTooLarge(limit:)`` for more.
- A request may take ``URLSessionHTTPClient/localNetworkResourceTimeout`` in all.

```swift
let client: URLSessionHTTPClient = URLSessionHTTPClient.localNetwork()
```

### Requests without credentials

``UnauthenticatedHTTPClient`` is a client that can't carry credentials, for requests to
addresses that mustn't receive them, such as every address Hub discovery asks. It's made only
from a ``URLSessionHTTPClient``, so a client that adds credentials can't take its place, and
it refuses a request that carries an `Authorization` header, a user name or password in its
URL, or one its session adds, with ``HTTPClientError/credentialsRefused``.

### Redirect policies

Requests without credentials follow the client's ``RedirectPolicy``:

- ``RedirectPolicy/followAll``, the default, follows redirects as the session does. An HTTPS
  request that ends at an address that isn't HTTPS throws ``HTTPClientError/insecureRedirect``,
  but that's checked after the response arrives, when the session has already sent the request
  to every address in between, so a chain from HTTPS through HTTP and back to HTTPS on another
  host passes.
- ``RedirectPolicy/sameOriginHTTPSOnly`` decides before following each redirect, and follows
  it only to HTTPS at the request's own host and port. A downgrade throws
  ``HTTPClientError/insecureRedirect`` and another host or port throws
  ``HTTPClientError/redirectRefused``, without sending the request there. Use it for a download
  whose integrity rests on HTTPS to the expected host, such as a file checked only against a
  hash fetched from the same place.
- ``RedirectPolicy/refuseAll`` follows none. Requests with credentials always get it.

```swift
let client: URLSessionHTTPClient = URLSessionHTTPClient(redirectPolicy: .sameOriginHTTPSOnly)
```

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
- ``UnauthenticatedHTTPClient``
- ``BasicAuthenticationHTTPClient``
- ``RedirectPolicy``
