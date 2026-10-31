# InsteonCLI

`insteon`, a command for driving an Insteon Hub or modem, and its devices, from a terminal on your home network. It's built on InsteonCore, the one library in this package it depends on, which opens the Hub or modem, finds Hubs, keeps the devices it has identified, links them, and names products and events from the Insteon device catalog, with the package's lower-level libraries underneath.

```sh
swift run insteon --hub 192.168.1.20 info
```

## Installing

```sh
Scripts/install-insteon.sh            # into ~/.local/bin
Scripts/install-insteon.sh /opt/local # into /opt/local/bin
```

The script, run from the package's root, builds the command for release and copies it into `PREFIX/bin`, `~/.local/bin` by default, together with `swift-insteon_InsteonDeviceCatalog.bundle` (`.resources` on Linux), the Insteon device catalog the command names products from. The bundle has to stay next to the command. Without it, the command still runs, prints a one-line warning, and leaves product names out. The script needs no `sudo`; put `PREFIX/bin` on your `PATH`. It then runs `insteon catalog update`, so installing also fetches the latest compatible catalog; offline, it says so and the bundled copy is used.

## Connecting

- `--hub HOST[:PORT]`: a Hub 2245 or Hub 2242 on the local network, by its private IPv4 address, as described below. Without `--hub`, the host comes from `INSTEON_HUB_HOST`, and a host without a port takes it from `INSTEON_HUB_PORT`, or else uses the Hub's port, 25105.
- `--serial PATH`: a PowerLinc Modem or USB Adapter on a serial or USB port, such as `/dev/ttyUSB0`, on macOS and Linux.
- `--env-file PATH`: the environment file to read in place of the default one, described below.

The Hub's user name and password, printed on it, come only from the environment variables `INSTEON_HUB_USERNAME` and `INSTEON_HUB_PASSWORD`, never from the command line, where they'd end up in shell history and process lists. The command never prints them. You can keep them in an environment file in your configuration directory, `$XDG_CONFIG_HOME/insteon/env`, or `~/.config/insteon/env` when `XDG_CONFIG_HOME` isn't set:

```sh
# ~/.config/insteon/env
INSTEON_HUB_USERNAME=your-hub-user-name
INSTEON_HUB_PASSWORD=your-hub-password
INSTEON_HUB_HOST=192.168.1.20
```

Make it readable only by you with `chmod 600 ~/.config/insteon/env`. The command reads the file only if you own it and no one else can write to it, and warns if others can read it. It never reads a file from the current directory, so a project you clone can't point the command, and your password, at another Hub. `--env-file PATH` reads another file, with the same checks.

Each line is `KEY=VALUE`, optionally after `export`; lines starting with `#` are comments. A value can be wrapped in single or double quotes, and nothing in it is expanded. A variable set in the environment wins over the file.

The command sends the Hub's user name and password only to an IPv4 address in `10.0.0.0/8`, `172.16.0.0/12` or `192.168.0.0/16`, where a Hub on a home network is, whether the address comes from `--hub` or `INSTEON_HUB_HOST`. A host name, an IPv6, loopback or link-local address, and a public address, such as a mistyped one, are refused before anything is sent, and there's no option to allow them. Through a VPN, give the Hub's address on the home network. Requests go to the Hub directly, never through a proxy, which would read the password. On Linux, where `http_proxy` or `all_proxy` can name a proxy the command can't turn off, it refuses to connect unless `no_proxy` names the Hub's address.

Before it connects, the command prints the Hub's address to standard error, as `Connecting to the Hub at HOST:PORT`, so you can see where the password is going.

The Hub's interface is plain HTTP, so the password is readable on the network: use it only on a network you trust.

## Commands

| Command | What it does |
| --- | --- |
| `discover [--local] [--insteon-connect] [--all] [--identify [HOST[:PORT]]]` | Finds Hubs by asking the addresses on the local network, stopping at the first Hub unless `--all` is given, with progress on standard error. `--insteon-connect` asks Insteon Connect instead, which lists the Hubs that reported from your network with their Insteon IDs and models, and shares your network's public IP address with Insteon; give both options for both ways. `--identify` asks Hubs found at a private address for Get IM Info with your configured credentials, which sends them the password unencrypted: it asks you before each Hub on port 25105 and stops at the first Hub that rejects the password. `--identify HOST[:PORT]` asks only that Hub, and is how to identify one without a terminal to answer at. |
| `info` | The modem's Get IM Info: its Insteon ID, category, subcategory and firmware version, and the product the Insteon device catalog has for them. |
| `links [--identify]` | Reads the modem's whole ALL-Link database and lists each record, with the product of each device whose identity is known. `--identify` asks each device with ID Request. |
| `link ADDRESS [--two-way]` | Links a device by its Insteon address, without its SET button: a device the catalog says is a light or switched load is turned fully on with Light On, so it links with full on as its on-level, and any other device, such as an I/O module or a lock, links with whatever on-level it captures; then the modem starts ALL-Linking as controller and sends the device Enter Linking Mode, extended for i2CS. A device that doesn't answer is linked with its SET button instead. A device the catalog says can control, or any device with `--two-way`, is then linked back with the modem as its responder, unless `--one-way` is given. |
| `link [--group N] [--controller \| --responder \| --either] [--two-way \| --one-way] [--timeout SECONDS]` | Links whichever device's SET button is pressed, waiting 4 minutes by default. With `--responder`, the device goes first: the command says how to put it into linking mode, and starts the modem when you press Return. As with `link ADDRESS`, a device the catalog says can control, or any device with `--two-way`, is then linked back with the modem as its responder, unless `--one-way` is given. |
| `link --cancel` | Takes the modem out of linking mode with Cancel ALL-Linking. |
| `unlink [ADDRESS] [--group N] [--controller \| --responder] [--timeout SECONDS]` | Removes a link with the device's SET button. With `--responder`, the device goes into unlinking mode first, with its own steps when its identity is known; with `ADDRESS`, only that device's unlink is accepted, and without `--group` the group is the one the modem's records for the device show. Afterward, it says which groups still link the device. |
| `unlink ADDRESS --all [--timeout SECONDS]` | Removes every link between the modem and the device, in each group the modem's ALL-Link database has for it and in both directions, without its SET button. For a link the device controls, the device is sent Enter Unlinking Mode and the modem joins as responder; for a link in one of the modem's groups, the modem starts ALL-Linking in unlinking mode and the device is sent Enter Linking Mode. Nothing is written to either database directly. If a link isn't removed, it says which are left and how to remove them with the SET button. |
| `remove ADDRESS [--scan] [--force-modem-side] [--yes] [--timeout SECONDS]` | Removes a device from the network: every link between it and the modem, as `unlink ADDRESS --all` removes them, with the modem's group 0 last; then, once the modem's ALL-Link database has no links with it, the identity cache forgets its identity, state and the modem's records for it; then it prints the catalog's factory reset steps for the device, which the command never runs. It asks first, and needs `--yes` without a terminal. `--scan` also reads the ALL-Link databases of the other devices the cache knows and lists the records that still name the device, without changing them. If a link isn't removed, or the modem still has links with the device, it says which and how to remove them, keeps the device and fails; `--force-modem-side`, for a device that's gone, deletes the modem's records for it with Manage ALL-Link Record instead and lists them. `unlink ADDRESS --all` removes the links and keeps the device. |
| `device ADDRESS id` | Get Insteon Engine Version, ID Request and Product Data Request, with the catalog's product. |
| `device ADDRESS ping` | Ping, with the time the device took to answer. |
| `device ADDRESS on [LEVEL%] [--fast]` | Light On, fully or to a level. A device the catalog says is on/off only turns on. `--fast` sends Light On Fast, which ignores the ramp rate, when the catalog lists it for the device. |
| `device ADDRESS off [--fast]` | Light Off, or Light Off Fast. |
| `device ADDRESS instant LEVEL%` | Light Instant Change, when the catalog lists it. An on/off device turns on, or off at 0%. |
| `device ADDRESS status` | Light Status Request: the device's level, or on or off for an on/off device. |
| `device ADDRESS beep` | Beep. A device whose command set doesn't list it is sent it anyway, with a note. |
| `device ADDRESS links` | Reads the device's ALL-Link database, with what each record's data means when the catalog describes the device. |
| `device ADDRESS settings [--advanced]` | Reads the settings the catalog describes for the device, grouped by section, as described below. |
| `device ADDRESS set NAME VALUE [--button N]` | Changes a setting, then reads it back and prints the old and new values. |
| `device ADDRESS send CMD1 CMD2 [--extended [D1 ... D14]] [--no-checksum] [--wait SECONDS]` | Sends a direct message as given and prints the ACK or NAK and what the device sends in the next 3 seconds, for exploring. |
| `scene GROUP on\|off`, `group GROUP on\|off` | Send ALL-Link Command with Light On or Light Off to one of the modem's groups, saying how many responders the modem's ALL-Link database lists for it and which didn't acknowledge their cleanup. |
| `beep [--double]` | The modem's Beep; `--double` beeps twice on later firmware. |
| `modem send HEX [--force] [--wait SECONDS]` | Writes a serial command as given, such as `0277`, and prints what the modem sends back, for exploring. |
| `watch [--raw]` | Prints what the modem hears until Control-C, with devices' group commands read as the catalog's named events and SET Button Pressed named. `--raw` adds each message's bytes. |
| `catalog` | Prints the version of the bundled Insteon device catalog, the version of the cached copy or `none`, and which copy is in use. Needs no Hub or modem. |
| `catalog update` | Downloads the latest published Insteon device catalog into the cache directory when it's in the format the command reads and differs from the copy in use, as described below. Needs no Hub or modem. |

The modem's group is 0 unless `--group` is given, as Insteon's Hub app links devices. Links made by earlier versions of the command are in group 1: `insteon unlink ADDRESS` finds them from the modem's records, and `insteon unlink --group 1` removes one without an address. `--json` prints JSON for `discover`, `info`, `links`, `link`, `unlink`, `remove` and `device ... id`, `status`, `links` and `settings`; `link` always prints one object, `{"links":[…],"legs":[…]}`: `links` holds every link the modem reported, in order, and `legs` each of the catalog's links to a Hub with its `modemRole`, `modemGroup`, `deviceGroup`, `status` (`linked`, `failed` or `notRun`), `joinedBy` and `error`, or is empty when the device wasn't linked by them. `unlink --all` prints an array of the links it removed. `insteon --help` and `insteon COMMAND --help` print help.

Control-C stops a command cleanly: `link`, `unlink` and `remove` take the modem out of linking mode first. Press it again to stop at once.

### Settings

`insteon device ADDRESS settings` reads what the Insteon device catalog describes for the device's command set: each Get Operating Flags query its flags and readings need, and extended Get for button 1, and for each of the device's other groups when some values are per button. It prints them under the catalog's sections, in the catalog's order, with each value shown through its value table, unit and scale, its default when the catalog gives one, and whether it's writable:

```text
$ insteon device 4D.5E.6F settings
Settings of 4D.5E.6F, Dimmer Switch 2477D (SwitchLinc Dimmer):

Load
  Resume dim:              off    writable
  Ramp rate:               0.5 s  writable
  On-level:                100%   writable

LEDs
  Blink LED when sending:  on     writable
  LED brightness:          64     writable
```

A setting the device didn't report reads "not reported". Settings the catalog marks advanced, such as the powerline's timing and X10, are shown only with `--advanced`. `--json` prints each setting with its section, name, label, button, value, byte, default and whether it's writable.

`insteon device ADDRESS set NAME VALUE` takes the catalog's name, such as `rampRate`, or its label in any case, such as `"ramp rate"`. A flag takes `on` or `off`; a value takes a label of its value table, such as `0.5s`, a number in its unit, such as `50%`, buttons such as `1,3`, or a byte such as `0x1C`. `--button N` picks the button or group of a per-button value. The command refuses a setting the catalog gives no way to write, and says why. It never writes the flags that turn off a device's radio or powerline or require a checksum in every message, which can cut the device off from the modem, so `settings` shows them as read-only; and it only turns the programming lock off, never on. A value whose byte holds those flags, such as an open/close sensor's configuration byte, is refused when it would turn the programming lock on or change one of the others. Set Operating Flags goes to an i2CS device as an extended message with a checksum.

### Exploring

`device ADDRESS send` and `modem send` send what you give them, to learn what a device or modem does that the catalog doesn't describe yet. `modem send` refuses, without `--force`, a command number the package doesn't know and commands that change or erase what the modem keeps or stop it answering, such as Reset the IM (`0x67`), Manage ALL-Link Record (`0x6F`) and Write Database (`0x76`). It also refuses Start ALL-Linking (`0x64`) with link code `0xFF`, which deletes links, and a message (`0x62`) that writes to a device, which `device ADDRESS set` and `device ADDRESS send` are for: Read/Write ALL-Link Database (`0x2F`), Set Operating Flags (`0x20`) and Extended Set/Get (`0x2E`) with D2 other than `0x00`. A command must have the length its number calls for, counting `0x02`: 8 bytes for a standard message and 22 for an extended one, and 2 or 3 for Beep (`0x77`). What you learn belongs in the catalog, marked as observed.

### Naming devices

The command names a device only from the identity it reported: its category, subcategory and firmware version, from an ID Request or from the modem's ALL-Linking Completed report. It never reads them from the data bytes of the modem's ALL-Link records, which don't hold them reliably. Identities that `link`, `links --identify`, `device ADDRESS id` and `watch` learn are kept in `$XDG_CACHE_HOME/insteon/identities.json`, or `~/.cache/insteon/identities.json`, readable only by you. `links`, `device ADDRESS links` and `device ADDRESS id` also keep in it the modem's and devices' ALL-Link databases, each device's engine, last level and the time it last answered, and the Hub's address, port and Insteon ID, so `device ADDRESS links` shows a device's ALL-Link database without reading it again while the device reports the same ALL-Link database delta. The file never holds the Hub's user name or password; delete it to forget what it holds. A file in a format the command doesn't read is left as it is, with one warning a run when an identity can't be remembered. A symbolic link at the file's path is left as it is too, with a warning, and is never replaced.

### Updating the catalog

The command names products and events from the Insteon device catalog. A copy ships in the bundle next to the command; `insteon catalog update` brings newer catalog data without a new release of the package:

```text
$ insteon catalog update
Checking https://brandtdaniels.github.io/insteon-device-catalog/v0/ for a newer Insteon device catalog...
Updated the Insteon device catalog to 0.6.12.

$ insteon catalog
Bundled:  0.6.11
Cached:   0.6.12
In use:   cached
```

It reads the catalog's published manifest over HTTPS, and downloads the catalog only when its version has the same MAJOR.MINOR as the bundled copy, the format the command reads, and its SHA-256 differs from the copy in use. A download is used only if it matches the manifest's SHA-256 and reads as a catalog. It's kept in `$XDG_CACHE_HOME/insteon/catalog.json`, or `~/.cache/insteon/catalog.json`, with its version in `catalog-version.json` beside it, both readable only by you. They hold only the public catalog; delete them to go back to the bundled copy.

Other commands use the cached copy when it has the bundled copy's MAJOR.MINOR and a PATCH at least as high, and the bundled copy otherwise, such as after installing a newer release of the package. A cached copy that can't be read gets a one-line warning, and the bundled copy is used. A catalog published in a newer format needs a newer swift-insteon; `catalog update` says so and keeps the current copy. A published catalog older than the copy in use, or than the bundled copy, isn't downloaded, so a stale cache or a rolled-back site can't take back newer data; `catalog update` says so and keeps the current copy.

`catalog update` asks only the catalog's site. It needs no Hub or modem, doesn't read the environment file or the Hub's settings, and sends no credentials. It follows a redirect only to HTTPS on the catalog's own host and port, deciding before each one; any other redirect fails the update and keeps the current copy, since the catalog isn't signed and its integrity rests on HTTPS to the expected host plus the manifest's SHA-256. It exits with status 1 when the catalog can't be downloaded.

### Which messages reach the modem

The modem hears messages sent to it, and group broadcasts from devices it has a responder record for. A device linked with the modem only as its controller, as `insteon link --one-way` does, sends the modem nothing when its buttons are pressed. `insteon link` links a device the catalog says can control back, with the modem as its responder, so `insteon watch` hears it; for another device, use `insteon link ADDRESS --two-way` or `insteon link --responder`.

The command exits with status 0 on success, 1 when something fails, such as a device that doesn't answer, 64 for a command line or configuration it can't use, and 130 when interrupted.

## Example

```text
$ swift run insteon --hub 192.168.1.20 info
Connecting to the Hub at 192.168.1.20:25105
Insteon ID:   1A.2B.3C
Category:     0x03 (Network Bridges)
Subcategory:  0x33
Firmware:     0x45
Product:      Hub 2245 (Hub 2)

$ swift run insteon --hub 192.168.1.20 link
Connecting to the Hub at 192.168.1.20:25105
The modem is in linking mode for group 0.
Now press and hold the SET button of the device until it beeps or its light blinks.
Waiting up to 240 seconds; Control-C stops.
Linked 4D.5E.6F in group 0, modem as controller.
Category:     0x01 (Dimmable Lighting Control)
Subcategory:  0x20
Firmware:     0x41
Product:      Dimmer Switch 2477D (SwitchLinc Dimmer)

$ swift run insteon --hub 192.168.1.20 device 4D.5E.6F on 50%
Connecting to the Hub at 192.168.1.20:25105
Turned 4D.5E.6F on at 50%.
```

## Layout

- `Sources/insteon`: the command, which runs what the command line asks for
- `Sources/InsteonCLISupport`: reading the command line, finding and checking the environment file and reading its variables, choosing the modem, where the identity cache is kept, choosing between the bundled and cached catalogs, and the text the command prints from the catalog, as plain functions the tests in `Tests/InsteonCLISupportTests` cover
