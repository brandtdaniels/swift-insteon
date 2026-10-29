# InsteonCLI

`insteon`, a command for driving an Insteon Hub or modem, and its devices, from a terminal on your home network. It's built on the libraries in this package: InsteonHubClient and InsteonModem to talk to the modem, InsteonLinking to link devices, InsteonHubDiscovery to find Hubs, and InsteonDeviceCatalog to name products and events.

```sh
swift run insteon --hub 192.168.1.20 info
```

## Installing

```sh
Scripts/install-insteon.sh            # into ~/.local/bin
Scripts/install-insteon.sh /opt/local # into /opt/local/bin
```

The script, run from the package's root, builds the command for release and copies it into `PREFIX/bin`, `~/.local/bin` by default, together with `swift-insteon_InsteonDeviceCatalog.bundle` (`.resources` on Linux), the Insteon device catalog the command names products from. The bundle has to stay next to the command. Without it, the command still runs, prints a one-line warning, and leaves product names out. The script needs no `sudo`; put `PREFIX/bin` on your `PATH`.

## Connecting

- `--hub HOST[:PORT]`: a Hub 2245 or Hub 2242 on the local network. Without `--hub`, the host comes from `INSTEON_HUB_HOST`, and a host without a port takes it from `INSTEON_HUB_PORT`, or else uses the Hub's port, 25105.
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

Before it connects, the command prints the Hub's address to standard error, as `Connecting to the Hub at HOST:PORT`, so you can see where the password is going.

The Hub's interface is plain HTTP, so the password is readable on the network: use it only on a network you trust.

## Commands

| Command | What it does |
| --- | --- |
| `discover [--local] [--insteon-connect] [--all] [--identify]` | Finds Hubs by asking the addresses on the local network, stopping at the first Hub unless `--all` is given, with progress on standard error. `--insteon-connect` asks Insteon Connect instead, which lists the Hubs that reported from your network with their Insteon IDs and models, and shares your network's public IP address with Insteon; give both options for both ways. `--identify` asks each Hub found at a private address for Get IM Info with your configured credentials, which sends the password to each one. |
| `info` | The modem's Get IM Info: its Insteon ID, category, subcategory and firmware version, and the product the Insteon device catalog has for them. |
| `links [--identify]` | Reads the modem's whole ALL-Link database and lists each record, with the product of each device whose identity is known. `--identify` asks each device with ID Request. |
| `link ADDRESS [--two-way]` | Links a device by its Insteon address, without its SET button: the modem starts ALL-Linking as controller and sends the device Enter Linking Mode, extended for i2CS. A device that doesn't answer is linked with its SET button instead. A device the catalog says can control, or any device with `--two-way`, is then linked back with the modem as its responder. |
| `link [--group N] [--controller \| --responder \| --either] [--two-way] [--timeout SECONDS]` | Links whichever device's SET button is pressed, waiting 4 minutes by default. With `--responder`, the device goes first: the command says how to put it into linking mode, and starts the modem when you press Return. |
| `link --cancel` | Takes the modem out of linking mode with Cancel ALL-Linking. |
| `unlink [ADDRESS] [--group N] [--controller \| --responder] [--timeout SECONDS]` | Removes a link with the device's SET button. With `--responder`, the device goes into unlinking mode first, with its own steps when its identity is known; with `ADDRESS`, only that device's unlink is accepted. |
| `device ADDRESS id` | Get Insteon Engine Version, ID Request and Product Data Request, with the catalog's product. |
| `device ADDRESS ping` | Ping, with the time the device took to answer. |
| `device ADDRESS on [LEVEL%]` | Light On, fully or to a level. A device the catalog says is on/off only turns on. |
| `device ADDRESS off` | Light Off. |
| `device ADDRESS status` | Light Status Request: the device's level, or on or off for an on/off device. |
| `device ADDRESS links` | Reads the device's ALL-Link database, with what each record's data means when the catalog describes the device. |
| `watch [--raw]` | Prints what the modem hears until Control-C, with devices' group commands read as the catalog's named events and SET Button Pressed named. `--raw` adds each message's bytes. |

The modem's group is 0 unless `--group` is given, as Insteon's Hub app links devices. `--json` prints JSON for `discover`, `info`, `links`, `link`, `unlink` and `device ... id`, `status` and `links`; `link --two-way` prints an array of both links. `insteon --help` and `insteon COMMAND --help` print help.

Control-C stops a command cleanly: `link` and `unlink` take the modem out of linking mode first. Press it again to stop at once.

### Naming devices

The command names a device only from the identity it reported: its category, subcategory and firmware version, from an ID Request or from the modem's ALL-Linking Completed report. It never reads them from the data bytes of the modem's ALL-Link records, which don't hold them reliably. Identities that `link`, `links --identify` and `device ADDRESS id` learn are kept in `$XDG_CACHE_HOME/insteon/identities.json`, or `~/.cache/insteon/identities.json`, readable only by you. The file holds only Insteon addresses and identities; delete it to forget them.

### Which messages reach the modem

The modem hears messages sent to it, and group broadcasts from devices it has a responder record for. A device linked with the modem only as its controller, as `insteon link` does by default, sends the modem nothing when its buttons are pressed; link the modem as its responder too, with `insteon link ADDRESS --two-way` or `insteon link --responder`, for `insteon watch` to hear it.

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
- `Sources/InsteonCLICore`: reading the command line, finding and checking the environment file and reading its variables, choosing the modem, the identity cache's format, and the text the command prints from the catalog, as plain functions the tests in `Tests/InsteonCLICoreTests` cover
