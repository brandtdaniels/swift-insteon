# InsteonNetworking

The HTTP abstraction the Insteon clients send requests through.

- `HTTPClient`: an async protocol for sending a request and getting back `HTTPResponse`
- `URLSessionHTTPClient`: the default implementation, an adapter over `URLSession`
- `BasicAuthenticationHTTPClient`: a decorator that adds HTTP basic authentication to any `HTTPClient`

`URLSessionHTTPClient` never follows a redirect for a request with credentials, such as an `Authorization` header: it throws `HTTPClientError.redirectRefused` instead, so the credentials reach only the address the request named. A Hub never redirects its own requests. Another `HTTPClient` that sends credentials must refuse redirects the same way.

Requests without credentials follow the client's `RedirectPolicy`. The default, `.followAll`, follows redirects as the session does and only checks afterwards that an HTTPS request ended at HTTPS, by which time the session has already sent it to every address in between. `.sameOriginHTTPSOnly` decides before each redirect and follows it only to HTTPS at the request's own host and port, so a downgrade, even for one step, or another host or port fails the request without it being sent there. `.refuseAll` follows none. `InsteonDeviceCatalog`'s updater uses `.sameOriginHTTPSOnly`, since a downloaded catalog is checked only against a SHA-256 fetched from the same site.

See the DocC catalog in `Sources/InsteonNetworking/InsteonNetworking.docc` for the full documentation.
