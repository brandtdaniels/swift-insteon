# InsteonNetworking

The HTTP abstraction the Insteon clients send requests through.

- `HTTPClient`: an async protocol for sending a request and getting back `HTTPResponse`
- `URLSessionHTTPClient`: the default implementation, an adapter over `URLSession`
- `BasicAuthenticationHTTPClient`: a decorator that adds HTTP basic authentication to any `HTTPClient`
- `UnauthenticatedHTTPClient`: a client that can't carry credentials, for requests to addresses that mustn't receive them

`URLSessionHTTPClient` never follows a redirect for a request with credentials, such as an `Authorization` header: it throws `HTTPClientError.redirectRefused` instead, so the credentials reach only the address the request named. A Hub never redirects its own requests. Another `HTTPClient` that sends credentials must refuse redirects the same way.

Requests without credentials follow the client's `RedirectPolicy`. The default, `.followAll`, follows redirects as the session does and only checks afterwards that an HTTPS request ended at HTTPS, by which time the session has already sent it to every address in between. `.sameOriginHTTPSOnly` decides before each redirect and follows it only to HTTPS at the request's own host and port, so a downgrade, even for one step, or another host or port fails the request without it being sent there. `.refuseAll` follows none. `InsteonDeviceCatalog`'s updater uses `.sameOriginHTTPSOnly`, since a downloaded catalog is checked only against a SHA-256 fetched from the same site.

`URLSessionHTTPClient.localNetwork()` is the client for devices on the local network, such as a Hub. Its session of its own sends each request directly, never through a proxy, which would read a Hub's credentials; keeps no cookies, credentials or cache; follows no redirects; reads at most 64 KiB of an answer; and limits a request's total time. Linux reads its proxy from the environment and can't turn it off, so there the client refuses a request a proxy would carry; naming the device's address in `no_proxy` sends it directly.

See the DocC catalog in `Sources/InsteonNetworking/InsteonNetworking.docc` for the full documentation.
