# InsteonSerialCommand

This package contains types that enable the formation of an Insteon serial command. 

## Examples

```
let insteonId = InsteonIdentifier(0xAA, 0xBB, 0xCC)
  
let command = StandardLengthDirectCommand.lightOn(
  level: 0xFF
).command

let standardMessage = StandardLengthMessage(
  to: insteonId,
  command: command
)

let serialCommand = SerialCommand(
  .sendInsteonStandardMessage(
    message: standardMessage
  )
)

print(serialCommand.stringValue)

// Outputs: 0262AABBCC0F1100

```
