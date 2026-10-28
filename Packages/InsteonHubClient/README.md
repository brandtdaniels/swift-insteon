# InsteonHubClient

Control INSTEON devices through an INSTEON Hub on your local network: model 2245, or models 2242 and 2243 (the Hub Pro), which are built on the same foundations.

- `HubConnection`: a `ModemConnection` to the Hub's built-in modem, so a `Modem` from InsteonModem drives a Hub just like a USB or serial modem
- `Hub`: the Hub's HTTP interface underneath, which writes bytes to the modem and reads and clears the buffer of its replies
- `HubEndpoint`: the Hub's host and port (25105 by default)
- `HubBuffer` and `HubBufferCursor`: parse the reply buffer and pick out what's new since the last read

The Hub requires the user name and password printed on it. Keep them out of source code; load them from the keychain or your app's configuration.

See the DocC catalog in `Sources/InsteonHubClient/InsteonHubClient.docc` for the full documentation.
