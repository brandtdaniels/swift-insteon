# Conventions

How the packages name Insteon's products, commands and documents, so the docs read the same
everywhere. `repo-check terms` checks the forms it can, and CI runs it.

## Products

- **Insteon**, never INSTEON.
- **The name, then the model:** Hub 2242, Hub 2245, Hub Pro 2243, PowerLinc Modem 2413U,
  PowerLinc Controller 2414S, USB Adapter 2448A7, Leak Sensor 2852. No parentheses around the
  model, and no `-222` or other regional suffix unless it tells two products apart.
- **Product names** come from insteon.com, as the Insteon device catalog gives them, with the
  Linc name as an alias: Dimmer Switch 2477D (SwitchLinc Dimmer). Two exceptions keep the names
  Insteon's developer documents use, because the packages are built around them: the
  **PowerLinc Modem** (2412 and 2413) and the **PowerLinc Controller** (2414).
- **ICON**, as Insteon's device lists print the product line.
- Say **modem** in prose. Keep IM only inside Insteon's command names, such as Get IM Info.

## Protocol

- Engines: **i1, i2, i2CS, i3**. The Swift case and the catalog's JSON value stay `i2cs`.
- **ALL-Link**, **ALL-Linking**, **ALL-Link group**, **ALL-Link database**, and **ALL-Link
  cleanup** (ALL-Link Cleanup in report names). Never "link database" on its own.
- **cleanup**, **SET button**, **SET Button Pressed**, **on-level**, **ramp rate**,
  **heartbeat**, **powerline**, **dual-band** (Dual-Band in product names).
- **ACK**, **NAK**, and **acknowledgment** in American spelling, in prose and in Swift names,
  though Insteon's documents spell it "acknowledgement".
- **Command names** as the Insteon Developer's Guide gives them: Light On, Light Off, Light
  Status Request, ID Request, Product Data Request, Get Operating Flags, Set Operating Flags,
  Enter Linking Mode, Get Insteon Engine Version, ALL-Link Recall, ALL-Link Alias 1 Low. Call
  cmd1 `0x2E` the **extended Get** and **extended Set**.
- **cmd1** and **cmd2** in prose; `command1` and `command2` are Swift and JSON names.
- **D1** through **D14** for user data, with ranges as "D1 through D14".
- **Byte values** as `0x11`: `0x` and two uppercase hexadecimal digits, in code font in docs.
  Byte sequences as space-separated pairs: `02 62 1A 2B 3C 0F 11 FF`. Addresses as `0x0FFF`.
- **Group numbers in decimal** in prose: group 1, group 254.
- **category** and **subcategory**, glossed once as DevCat and SubCat where it helps.

## Domain language

One vocabulary, from the protocol to the screen. Each layer uses the words below, and a word
means one thing. A change that needs a word this list lacks adds it here first.

**What is organized**

- **Insteon network:** one modem or Hub, with the devices linked to it. A user organizes and
  names these. A local network (Ethernet or wifi) can hold several, so can a computer with USB
  or serial modems. Say **local network** for the Ethernet or wifi, and **network** alone for an
  Insteon network. A house is a place and never the name of a network: no "home" in names or
  prose for what a network holds, as `repo-check terms` checks for a few forms.
- **Service:** the program that serves one Insteon network over HTTP. A client reaches one
  service by one of its **routes**. A service can run on a computer, a phone or a container.
- **Client:** an app, command or program that talks to a service. A user **pairs** a client with
  a service. Pairing is only about clients. **Linking** is only about devices.
- **Device:** anything on an Insteon network. A modem or Hub is a device too, with the role of
  controller and the others on its network. **Endpoint:** one function of a device, a group or
  a button. A dimmer has one endpoint, a keypad has several.
- **Scene:** a group the modem controls and its members' stored levels and ramp rates. **Source**
  is what starts a scene and **member** is a device that answers it, in the service's JSON and in
  an app. The protocol layers keep **controller**, **responder** and **ALL-Link group**, the Developer's
  Guide's words, which also name the flags in a database record.
- **Schedule, timer, notification rule:** what a service runs at a time, after a delay, or when a
  device event matches.

**Shape**

- **Hierarchy** is what contains what: a user's networks, a network's devices, a device's
  endpoints. **Topology** is how things connect: the local network, and the powerline and radio
  paths between devices. Name containment a hierarchy, and paths a topology.
- The shape follows Matter and HomeKit where it can: a device is a node, an endpoint is an
  endpoint or service, a capability is a cluster or characteristic, an ALL-Link group is a group, a
  scene is a scene, and a schedule is an automation.

**The API**

- Say **HTTP API** or **JSON API**. Don't call it REST: it has no hypermedia, so by Fielding's
  definition it isn't. The routes table and the generated OpenAPI description are its contract.

## Documents

Cite each document by its own title, never as "the guide" alone.

| Document | Cite as |
| --- | --- |
| The 2009 protocol guide | Insteon Developer's Guide |
| The 2007 modem guide | Insteon Modem Developer's Guide |
| The Hub 2242's guide | Insteon Hub Developer's Guide |
| The 2007 command tables | Insteon Command Tables |
| The device lists | Insteon Device Categories and Product Keys (October 2008), Insteon Device Categories (January 2014) |
| The i2CS notes | Insteon Firmware Update i2CS Developer Notes |
| A product's notes | Its title's subject, then Developer Notes: Leak Sensor Developer Notes, KeypadLinc Developer Notes |
| HouseLinc's data | HouseLinc device catalog |

## Spelling and style

American English. Name no third-party projects. Every public declaration has a DocC comment.

Say what's true, not when it became true: no "now", "currently", "previously", "no longer",
"newly", or "new" for a change, such as "a new option". The prose outlives the change it
would date.

## Device knowledge

InsteonCore, the `insteon` command, the in-memory modem and their tests know no device: what a
device is and does comes from the Insteon device catalog. They don't name a real product or
operating flag, and a test builds its own catalog with invented names. `repo-check device-neutral`
checks it, with the words taken from the bundled catalog, and CI runs it. An exception is a line
in `Scripts/check-device-neutral-allowlist.txt`: the path, the word and the reason, separated by
tabs. The list only shrinks, so CI fails a pull request that adds one.
