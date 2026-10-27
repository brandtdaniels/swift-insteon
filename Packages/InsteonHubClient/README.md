# InsteonHubClient

Control INSTEON devices through an INSTEON Hub (model 2245) on your local network.

- `Hub`: sends serial commands to the Hub's modem, and reads and clears the buffer of its replies; conforms to `SerialCommandSender`
- `HubEndpoint`: the Hub's host and port (25105 by default)
- `HubBuffer` and `HubBufferCursor`: parse the reply buffer and pick out what's new since the last read

The Hub requires the user name and password printed on it. Keep them out of source code; load them from the keychain or your app's configuration.

See the DocC catalog in `Sources/InsteonHubClient/InsteonHubClient.docc` for the full documentation.
