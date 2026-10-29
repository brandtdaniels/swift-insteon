# InsteonCLI

`insteon`, a command for driving an Insteon Hub or modem, and its devices, from a terminal on your home network. It's built on the libraries in this package: InsteonHubClient and InsteonModem to talk to the modem, InsteonLinking to link devices, InsteonHubDiscovery to find Hubs, and InsteonDeviceCatalog to name products and events.

```sh
swift run insteon --hub 192.168.1.20 info
```

## Connecting

- `--hub HOST[:PORT]`: a Hub 2245 or Hub 2242 on the local network. Without `--hub`, the host comes from `INSTEON_HUB_HOST`, and a host without a port takes it from `INSTEON_HUB_PORT`, or else uses the Hub's port, 25105.
- `--serial PATH`: a PowerLinc Modem or USB Adapter on a serial or USB port, such as `/dev/ttyUSB0`, on macOS and Linux.

The Hub's user name and password, printed on it, come only from the environment variables `INSTEON_HUB_USERNAME` and `INSTEON_HUB_PASSWORD`, never from the command line, where they'd end up in shell history and process lists. The command never prints them. You can keep them in a `.env` file in the directory you run the command from:

```sh
# .env
INSTEON_HUB_USERNAME=your-hub-user-name
INSTEON_HUB_PASSWORD=your-hub-password
INSTEON_HUB_HOST=192.168.1.20
```

Each line is `KEY=VALUE`, optionally after `export `; lines starting with `#` are comments. A value can be wrapped in single or double quotes, and nothing in it is expanded. A variable set in the environment wins over the file. Add `.env` to your `.gitignore` so the password isn't committed, and keep the file readable only by you (`chmod 600 .env`).

The Hub's interface is plain HTTP, so the password is readable on the network: use it only on a network you trust.

## Commands

| Command | What it does |
| --- | --- |
| `discover [--local] [--insteon-connect]` | Finds Hubs by asking every address on the local network, and Insteon Connect, which lists the Hubs that reported from your network with their Insteon IDs. Both by default. |
| `info` | The modem's Get IM Info: its Insteon ID, category, subcategory and firmware version, and the product the Insteon device catalog has for them. |
| `links` | Reads the modem's whole ALL-Link database and lists each record, with the product a controller record names. |
| `link [--group N] [--controller \| --responder \| --either] [--timeout SECONDS]` | Puts the modem into linking mode with Start ALL-Linking and waits, 4 minutes by default, for someone to press and hold a device's SET button, then prints the device. |
| `link --cancel` | Takes the modem out of linking mode with Cancel ALL-Linking. |
| `unlink [--group N] [--controller \| --responder] [--timeout SECONDS]` | Puts the modem into unlinking mode and waits for a device's SET button. |
| `device ADDRESS id` | Get Insteon Engine Version, ID Request and Product Data Request, with the catalog's product. |
| `device ADDRESS ping` | Ping, with the time the device took to answer. |
| `device ADDRESS on [LEVEL%]` | Light On, fully or to a level. |
| `device ADDRESS off` | Light Off. |
| `device ADDRESS status` | Light Status Request: the device's level. |
| `device ADDRESS links` | Reads the device's ALL-Link database. |
| `watch [--raw]` | Prints what the modem hears until Control-C, with devices' group commands read as the catalog's named events. |

`--json` prints JSON for `discover`, `info`, `links`, `link`, `unlink` and `device ... id`, `status` and `links`. `insteon --help` and `insteon COMMAND --help` print help.

Control-C stops a command cleanly: `link` and `unlink` take the modem out of linking mode first. Press it again to stop at once.

The command exits with status 0 on success, 1 when something fails, such as a device that doesn't answer, 64 for a command line or configuration it can't use, and 130 when interrupted.

## Example

```text
$ swift run insteon --hub 192.168.1.20 info
Insteon ID:   1A.2B.3C
Category:     0x03 (Network Bridges)
Subcategory:  0x33
Firmware:     0x45
Product:      Hub 2245 (Hub 2)

$ swift run insteon --hub 192.168.1.20 link
The modem is in linking mode for group 1. Press and hold the device's SET button until it beeps or its light blinks. Waiting up to 240 seconds; Control-C stops.
Linked 4D.5E.6F in group 1.
Device:       4D.5E.6F
Modem role:   controller
Category:     0x01 (Dimmable Lighting Control)
Subcategory:  0x20
Firmware:     0x41
Product:      Dimmer Switch 2477D (SwitchLinc Dimmer)

$ swift run insteon --hub 192.168.1.20 device 4D.5E.6F on 50%
Turned 4D.5E.6F on at 50%.
```

## Layout

- `Sources/insteon`: the command, which runs what the command line asks for
- `Sources/InsteonCLICore`: reading the command line and `.env` files, and choosing the modem, as plain functions the tests in `Tests/InsteonCLICoreTests` cover
