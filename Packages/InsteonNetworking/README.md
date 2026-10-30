# InsteonNetworking

The HTTP abstraction the Insteon clients send requests through.

- `HTTPClient`: an async protocol for sending a request and getting back `HTTPResponse`
- `URLSessionHTTPClient`: the default implementation, an adapter over `URLSession`
- `BasicAuthenticationHTTPClient`: a decorator that adds HTTP basic authentication to any `HTTPClient`

`URLSessionHTTPClient` never follows a redirect for a request with credentials, such as an `Authorization` header: it throws `HTTPClientError.redirectRefused` instead, so the credentials reach only the address the request named. A Hub never redirects its own requests. Another `HTTPClient` that sends credentials must refuse redirects the same way.

See the DocC catalog in `Sources/InsteonNetworking/InsteonNetworking.docc` for the full documentation.
