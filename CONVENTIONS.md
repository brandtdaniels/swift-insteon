# Conventions

How the packages name Insteon's products, commands and documents, so the docs read the same
everywhere. `Scripts/check-terms.py` checks the forms it can, and CI runs it.

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
