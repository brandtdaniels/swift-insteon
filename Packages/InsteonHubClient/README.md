![Swift](https://github.com/brandtdaniels/InsteonHubClient/workflows/Swift/badge.svg)

# InsteonHubClient

This package allows you to send requests to an Insteon Hub.

Requests available are:

* Command Buffer Request
* Clear Command Buffer Request
* Sensor Status Request
* Standard Command Request (Synchronous)
* Extended Command Request (Synchronous)
* Extended Command Request w/ wait (Synchronous)
	* This is used when a response is required
* Update Hub Credentials Request

Other requests can be created as long as they conform to the `HubRequestProtocol`

## Future features

Future features could include:

* Deserialization of responses
* Handle sending commands and parsing responses

## Examples

```
let credentials = LoginCredentials(
  user: "username",
  password: "password"
)

let address = SocketAddress(
  host: "example.com",
  port: 25105
)

hubClient = HubClient(
  credentials: credentials,
  address: address,
  requestClient: mockRequestClient
)
    
let serialCommand = SerialCommand(.cancelAllLinking)

let hubRequest = SerialCommandRequest(serialCommand)

hubClient.send(hubRequest) { result in

  // Do something with result

}

```
