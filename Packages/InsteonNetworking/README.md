# InsteonNetworking

The HTTP abstraction the INSTEON clients send requests through.

- `HTTPClient`: an async protocol for sending a request and getting back `HTTPResponse`
- `URLSessionHTTPClient`: the default implementation, an adapter over `URLSession`
- `BasicAuthenticationHTTPClient`: a decorator that adds HTTP basic authentication to any `HTTPClient`

See the DocC catalog in `Sources/InsteonNetworking/InsteonNetworking.docc` for the full documentation.
