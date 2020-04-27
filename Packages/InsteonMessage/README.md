# InsteonMessage

This package contains types that enable the formation of an Insteon message. 

### Convenience

There are several convenience options such as message flag values for standard and extended message types, command types, and a string formatter for printing or network requests.

## Examples

```
let insteonId = InsteonIdentifier(0xAA, 0xBB, 0xCC)
  
let lightOnFiftyPercent = StandardLengthDirectCommand.lightOn(
  level: 0x80
)
  
let lightOnFiftyPercentMessage = StandardLengthMessage(
  to: insteonId,
  command: lightOnFiftyPercent.command
)

let rawString = Formatter.format(
  lightOnFiftyPercentMessage
)

print(rawString)

// Outputs: AABBCC0F1180

```

