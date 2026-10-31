# InsteonHubClient

Control Insteon devices through an Insteon Hub on your local network: the Hub 2245, or the Hub 2242 and Hub Pro 2243, which are built on the same foundations.

- `HubConnection`: a `ModemConnection` to the Hub's built-in modem, so a `Modem` from InsteonModem drives a Hub just like a USB or serial modem
- `Hub`: the Hub's HTTP interface underneath, which writes bytes to the modem and reads and clears the buffer of its replies
- `HubEndpoint`: the Hub's host and port (25105 by default)
- `HubBuffer` and `HubBufferCursor`: parse the reply buffer and pick out what's new since the last read

The Hub requires the user name and password printed on it. Keep them out of source code; load them from the keychain or your app's configuration. A Hub never redirects its own requests, so the default `URLSessionHTTPClient` refuses any redirect for a request carrying them and throws `HTTPClientError.redirectRefused`, and the credentials reach only the Hub's address. The default client, `URLSessionHTTPClient.localNetwork()`, goes to the Hub directly rather than through a proxy, which would read the credentials, keeps no cookies, credentials or cache, and limits each request's total time and the size of the Hub's answer. A `HubConnection` sends nothing more after the Hub first rejects the credentials.

See the DocC catalog in `Sources/InsteonHubClient/InsteonHubClient.docc` for the full documentation.
