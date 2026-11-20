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

- `--hub HOST[:PORT]`: a Hub 2245 or Hub 2242 on the local network, by its private IPv4 address, as described below. A Hub Pro at that address is read and controlled over its local HTTP interface instead, as described under Hub Pro below, and is asked for no user name or password. Without `--hub`, the host comes from `INSTEON_HUB_HOST`, and a host without a port takes it from `INSTEON_HUB_PORT`, or else uses the Hub's port, 25105.
- `--hub NAME`: a Hub kept in its own file, `hubs/NAME.env` in your configuration directory, described below. A value for `--hub` that isn't an IPv4 address is a name. A name uses the letters a-z, the digits 0-9, hyphen and underscore, 1 to 32 characters, so it can't hold a slash or a dot and can't reach outside that directory.
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

### Several Hubs

A network can have more than one Hub, such as a Hub 2 and a Hub Pro. Keep each Hub's settings in its own file in the `hubs` directory beside the environment file, `$XDG_CONFIG_HOME/insteon/hubs/NAME.env` or `~/.config/insteon/hubs/NAME.env`, in the same form and under the same checks as the environment file, and never read from the current directory:

```sh
# ~/.config/insteon/hubs/basement.env
INSTEON_HUB_USERNAME=your-hub-user-name
INSTEON_HUB_PASSWORD=your-hub-password
INSTEON_HUB_HOST=192.168.1.30
```

A Hub file can set `INSTEON_HUB_HOST` and `INSTEON_HUB_PORT`, so `insteon --hub basement info` needs no address. An address given with `--hub` still wins over a host in a file, and a variable set in the environment wins over the file. The file the command reads is the first of these that applies:

1. `--env-file PATH`.
2. `--hub NAME`.
3. The `INSTEON_HUB` environment variable, which names a Hub as `--hub NAME` does: `INSTEON_HUB=basement insteon info`.
4. The default file, `~/.config/insteon/env`, as before.

A name with no file is an error that names the file the command looked for and the Hub files that exist. `INSTEON_HUB` naming a file that doesn't exist is an error too; the command never falls back to the default file. `insteon hubs` lists the files, and `insteon discover` shows the file name and command to use for each Hub it finds. To run the server for several Hubs, run one server per Hub, each with its own `--env-file`.

Each line is `KEY=VALUE`, optionally after `export`; lines starting with `#` are comments. A value can be wrapped in single or double quotes, and nothing in it is expanded. A variable set in the environment wins over the file.

The command sends the Hub's user name and password only to an IPv4 address in `10.0.0.0/8`, `172.16.0.0/12` or `192.168.0.0/16`, where a Hub on a home network is, whether the address comes from `--hub` or `INSTEON_HUB_HOST`. A host name, an IPv6, loopback or link-local address, and a public address, such as a mistyped one, are refused before anything is sent, and there's no option to allow them. Through a VPN, give the Hub's address on the home network. Requests go to the Hub directly, never through a proxy, which would read the password. On Linux, where `http_proxy`, `HTTP_PROXY`, `all_proxy` or `ALL_PROXY` can name a proxy the command can't turn off, it refuses to connect unless `no_proxy` names the Hub's exact address, such as `no_proxy=192.168.1.20`; an address range there isn't read, and `*` counts only as the whole value.

Before it connects, the command prints the Hub's address to standard error, as `Connecting to the Hub at HOST:PORT`, so you can see where the password is going.

The Hub's interface is plain HTTP, so the password is readable on the network: use it only on a network you trust.

## Commands

| Command | What it does |
| --- | --- |
| `discover [--local] [--insteon-connect \| --insteon-stage] [--all] [--identify [HOST[:PORT]]]` | Finds Hubs and Hub Pros by asking the addresses on the local network, stopping at the first Hub unless `--all` is given, with progress on standard error. On macOS the search first browses Bonjour for a Hub Pro, which advertises itself as a HomeKit accessory; the Hub Pro's model comes from the Insteon device catalog, and the address Bonjour resolves is confirmed with the two reads below. Each address is asked for a Hub's page on the Hub's port and, for each port the catalog gives a Hub Pro's interface, a read of its root and, only when the root answers 401 without a `WWW-Authenticate` header, its settings. A Hub Pro is listed with its address and the versions it reports; use `--hub` with it to read and control its devices. `--insteon-connect` asks Insteon Connect instead, which lists the Hubs that reported from your network with their Insteon IDs and models, and `--insteon-stage` asks Insteon's staging service, which lists a Hub Pro that announces only there with its firmware; each sends your network's public IP address to that service, a run asks only one, and giving both is an error. Give `--local` with either for both ways. `--identify` asks Hubs found at a private address for Get IM Info with your configured credentials, which sends them the password unencrypted: it asks you before each Hub on port 25105 and stops at the first Hub that rejects the password, and it never sends a password to a Hub Pro. `--identify HOST[:PORT]` asks only that Hub, and is how to identify one without a terminal to answer at. Nothing `discover` sends carries credentials unless `--identify` does. |
| `hubs` | Lists the Hub files: the default file and each `hubs/NAME.env`, with the address each sets and a note, marking the default, which is the Hub `INSTEON_HUB` names or else the default file. A file that can't be used says why: others can write to it, another user owns it, it isn't a regular file, it can't be read, a line is malformed, or its name is unusable. It never shows a user name or a password, and needs no Hub. With no files it says where it looked and how to create one, and exits with status 0. |
| `info` | The modem's Get IM Info: its Insteon ID, category, subcategory and firmware version, and the product the Insteon device catalog has for them. |
| `links [--identify]` | Reads the modem's whole ALL-Link database and lists each record, with the product of each device whose identity is known. `--identify` asks each device with ID Request. |
| `link ADDRESS [--two-way]` | Links a device by its Insteon address, without its SET button: a device the catalog says is a light or switched load is turned fully on with Light On, so it links with full on as its on-level, and any other device, such as an I/O module or a lock, links with whatever on-level it captures; then the modem starts ALL-Linking as controller and sends the device Enter Linking Mode, extended for i2CS. A device that doesn't answer is linked with its SET button instead. A device the catalog says can control, or any device with `--two-way`, is then linked back with the modem as its responder, unless `--one-way` is given. |
| `link [--group N] [--controller \| --responder \| --either] [--two-way \| --one-way] [--timeout SECONDS]` | Links whichever device's SET button is pressed, waiting 4 minutes by default. With `--responder`, the device goes first: the command says how to put it into linking mode, and starts the modem when you press Return. As with `link ADDRESS`, a device the catalog says can control, or any device with `--two-way`, is then linked back with the modem as its responder, unless `--one-way` is given. When the modem reports a link other than the one asked for, such as one in another group, the command fails and keeps the identity the modem reported for the device, so `links` names its product. When the modem controls that link, the message gives its group and the `unlink ADDRESS --group N` command that removes it. |
| `link --cancel` | Takes the modem out of linking mode with Cancel ALL-Linking. |
| `unlink [ADDRESS] [--group N] [--controller \| --responder] [--timeout SECONDS]` | Removes a link with the device's SET button. With `--responder`, the device goes into unlinking mode first, with its own steps when its identity is known; with `ADDRESS`, only that device's unlink is accepted, and without `--group` the group is the one the modem's records for the device show. Afterward, it says which groups still link the device. |
| `unlink ADDRESS --all [--timeout SECONDS]` | Removes every link between the modem and the device, in each group the modem's ALL-Link database has for it and in both directions, without its SET button. For a link the device controls, the device is sent Enter Unlinking Mode and the modem joins as responder; for a link in one of the modem's groups, the modem starts ALL-Linking in unlinking mode and the device is sent Enter Linking Mode. Nothing is written to either database directly. If a link isn't removed, it says which are left and how to remove them with the SET button. |
| `link ADDRESS [--group N] --relay-state on\|off [--dry-run] [--yes] [--json]` | Links a relay so it records the state: a group On from the modem then sets the relay to it, and a group Off to the opposite. The device's main group must be a relay whose type the catalog says how it holds a state, in `stateHolding`, and the device must already be linked to the modem; a relay the catalog says nothing about is refused. The command shows what it will switch and put back, and asks first, naming each flag it turns off; `--yes` skips the question and is needed without a terminal, and `--dry-run` shows the plan and sends nothing more. When every flag of one of the catalog's sets that make every On and Off pulse the relay is on, the state is ignored, and the relay isn't switched and no flag is written. With `--json`, the object carries `relayState`, whose `groupOn` and `groupOff` are absent when the state was ignored. The relay is read again as it links, and nothing is switched when it doesn't match the plan shown. The relay, and whatever it controls, is switched unless it's already in the state, and its status read back; a flag that keeps the relay from holding a state is turned off first when the catalog lets linking change it. The device is linked in one link, not by the catalog's links to a Hub and never with its SET button. Then, however linking ends, a relay whose flag was turned off is returned to its rest state and the flag turned back on; a relay that holds a state keeps the state it recorded, and is switched back when linking fails or is canceled. Last, its responder record is read back to check the state. With `--database`, Data 1 of its responder record holds the state, `0xFF` for on and `0x00` for off, and the relay isn't switched. Without `--relay-state`, a relay is never switched. |
| `link ADDRESS --database [--dry-run] [--yes]` | Links the device by writing the records of the catalog's links to a Hub straight into its ALL-Link database and the modem's, without linking mode or the SET button, as described below. It shows the writes and asks first, and needs `--yes` without a terminal; `--dry-run` shows them and writes nothing. |
| `unlink ADDRESS --database [--orphans] [--dry-run] [--yes]` | Removes every link between the modem and the device by clearing the device's records of the modem and deleting the modem's records of the device, as described below. `--orphans` also clears the device's records that name a device the modem has no record of, which can be a working link with a device never linked to the modem, such as a 3-way switch or a keypad button. It asks first, as `link --database` does. |
| `remove ADDRESS [--scan] [--force-modem-side] [--yes] [--timeout SECONDS]` | Removes a device from the network: every link between it and the modem, as `unlink ADDRESS --all` removes them, with the modem's group 0 last; then, once the modem's ALL-Link database has no links with it, the identity cache forgets its identity, state and the modem's records for it; then it prints the catalog's factory reset steps for the device, which the command never runs. It asks first, and needs `--yes` without a terminal. `--scan` also reads the ALL-Link databases of the other devices the cache knows and lists the records that still name the device, without changing them. If a link isn't removed, or the modem still has links with the device, it says which and how to remove them, keeps the device and fails; `--force-modem-side`, for a device that's gone, deletes the modem's records for it with Manage ALL-Link Record instead and lists them. `unlink ADDRESS --all` removes the links and keeps the device. |
| `device ADDRESS id` | Get Insteon Engine Version, ID Request and Product Data Request, with the catalog's product. |
| `device ADDRESS ping` | Ping, with the time the device took to answer. |
| `device ADDRESS on [LEVEL%] [--fast]` | Light On, fully or to a level. A device the catalog says is on/off only turns on. `--fast` sends Light On Fast, which ignores the ramp rate, when the catalog lists it for the device. |
| `device ADDRESS off [--fast]` | Light Off, or Light Off Fast. |
| `device ADDRESS instant LEVEL%` | Light Instant Change, when the catalog lists it. An on/off device turns on, or off at 0%. |
| `device ADDRESS status` | Light Status Request: the device's level, or on or off for an on/off device. |
| `device ADDRESS beep` | Beep. A device whose command set doesn't list it is sent it anyway, with a note. |
| `device ADDRESS links` | Reads the device's ALL-Link database, with what each record's data means when the catalog describes the device. |
| `backup FILE [--force]` | Reads the modem's identity and ALL-Link database, then each device's: ID Request, Light Status Request and its ALL-Link database, every one a read, and writes them to `FILE` as JSON readable only by you, with a checksum. The file holds no Hub user name or password, token or address. A device that doesn't answer, rejects the modem or returns damaged records is in the file with the reason, listed when the command ends, which then exits with status 2. An existing `FILE` is never overwritten without `--force`, and Control-C writes nothing. For a Hub Pro it records the device list from its read endpoints, with each device marked as having no ALL-Link database to read. |
| `backup --check FILE` | Needs no modem. Checks that `FILE` parses, its format and checksum, and counts what it holds: the modem's links, the devices, and the devices with no whole ALL-Link database, which it lists. Exits with status 0 for a whole backup, 2 when devices have no database, and 1 when the checksum fails. |
| `transfer plan FILE [--merge \| --replace-database]` | Plans how the devices in a backup move to the connected modem, which has another address, and writes nothing. It prints every step grouped per device, each marked `readOnly`, `configuration`, `link` or `destructive`, with the exact record it would write. See Moving to another modem below. |
| `observe [ADDRESS] [--note TEXT] [--output PATH]` | Without an `ADDRESS` and with `--hub` naming a Hub Pro, records what the Hub Pro reports, as described under Hub Pro below. Otherwise records what a device did, as a small JSON file (`insteon-observation/1`) you can attach to an issue or a pull request, so others can help check the catalog. It asks only reads: Get Insteon Engine Version, ID Request, Product Data Request, the catalog's status request and its operating flag requests, and records for each whether the device answered, was silent or refused. A silent request, as from a battery device that is asleep, says the device may need to be awake and states nothing about it. The file holds no address of a device, the modem or a Hub, no host and no account data; a `--note` that looks like an address is refused. The file's `productKey` is the key the device reported, `none` only when it answered Product Data Request and reported no key, and absent when that request got no answer, was refused or wasn't made. The JSON goes to standard output, or to `--output PATH`, which is never overwritten; a summary goes to standard error. The format is `Schemas/insteon-observation-1.schema.json`, with `Schemas/insteon-observation-1.example.json` as an example. |
| `device ADDRESS selftest [--actuate] [--checklist]` | Checks that the device is healthy and set up as the catalog expects, as described below, and fails when a check does. |
| `device ADDRESS settings [--advanced]` | Reads the settings the catalog describes for the device, grouped by section, as described below. |
| `device ADDRESS set NAME VALUE [--button N]` | Changes a setting, then reads it back and prints the old and new values, and any other setting the write changed. |
| `device ADDRESS send CMD1 CMD2 [--extended [D1 ... D14]] [--no-checksum] [--wait SECONDS]` | Sends a direct message as given and prints the ACK or NAK and what the device sends in the next 3 seconds, for exploring. It sends the protected Set Operating Flags only where the device's catalog entry gives them another meaning, and never Poke, as described below. |
| `scene GROUP on\|off`, `group GROUP on\|off` | Send ALL-Link Command with Light On or Light Off to one of the modem's groups, saying how many responders the modem's ALL-Link database lists for it and which didn't acknowledge their cleanup. |
| `beep [--double]` | The modem's Beep; `--double` beeps twice on later firmware. |
| `modem send HEX [--force] [--wait SECONDS]` | Writes a serial command as given, such as `0277`, and prints what the modem sends back, for exploring. The modem's catalog entry says what the command does, and one that changes a setting, is destructive or isn't described needs `--force`. It never writes a message with the protected Set Operating Flags or Poke, as described below, even with `--force`. |
| `watch [--raw]` | Prints what the modem hears until Control-C, with devices' group commands read as the catalog's named events and SET Button Pressed named. `--raw` adds each message's bytes. |
| `catalog` | Prints the version of the bundled Insteon device catalog, the version of the cached copy or `none`, and which copy is in use. Needs no Hub or modem. |
| `catalog update` | Downloads the latest published Insteon device catalog into the cache directory when it's in the format the command reads and differs from the copy in use, as described below. Needs no Hub or modem. |

The modem's group is 0 unless `--group` is given, as Insteon's Hub app links devices. Links made by earlier versions of the command are in group 1: `insteon unlink ADDRESS` finds them from the modem's records, and `insteon unlink --group 1` removes one without an address. `--json` prints JSON for `discover`, `info`, `links`, `link`, `unlink`, `remove` and `device ... id`, `status`, `links`, `settings`, `set` and `selftest`; `link` always prints one object, `{"links":[…],"legs":[…]}`: `links` holds every link the modem reported, in order, and `legs` each of the catalog's links to a Hub with its `modemRole`, `modemGroup`, `deviceGroup`, `status` (`linked`, `failed` or `notRun`), `joinedBy` and `error`, or is empty when the device wasn't linked by them. `unlink --all` prints an array of the links it removed. `insteon --help` and `insteon COMMAND --help` print help.

Control-C stops a command cleanly: `link`, `unlink` and `remove` take the modem out of linking mode first. Press it again to stop at once.

### Settings

`insteon device ADDRESS settings` reads what the Insteon device catalog describes for the device's command set: each Get Operating Flags query its flags and readings need, and extended Get for button 1, and for each of the device's other groups when some values are per button. It prints them under the catalog's sections, in the catalog's order, with each value shown through its value table, unit and scale, its default when the catalog gives one, and whether it's writable:

```text
$ insteon device 4D.5E.6F settings
Settings of 4D.5E.6F, Example Dimmer 9101 (DemoLinc Dimmer):

Load
  Remember level:          off    writable
  Ramp rate:               0.5 s  writable
  On-level:                100%   writable

LEDs
  Flash LED when sending:  on     writable
  LED brightness:          64     writable
```

A setting the device didn't report reads "not reported". Settings the catalog marks advanced, such as the powerline's timing and X10, are shown only with `--advanced`. `--json` prints each setting with its section, name, label, button, value, byte, default and whether it's writable.

`insteon device ADDRESS set NAME VALUE` takes the catalog's name, such as `rampRate`, or its label in any case, such as `"ramp rate"`. A flag takes `on` or `off`; a value takes a label of its value table, such as `0.5s`, a number in its unit, such as `50%`, buttons such as `1,3`, or a byte such as `0x1C`. `--button N` picks the button or group of a per-button value. The command refuses a setting the catalog gives no way to write, and says why. It never writes a flag the catalog keeps, such as one that turns off a device's radio or powerline or requires a checksum in every message, which can cut the device off from the modem, so `settings` shows them as read-only; and a flag the catalog guards as never set, such as one that locks linking from the device itself, it only turns off, never on. A value whose byte holds those flags, such as a sensor's configuration byte, is refused when it would turn a never-set flag on or change a kept one. Set Operating Flags goes to an i2CS device as an extended message with a checksum.

A write can change other settings too, as some devices turn a flag on when a value that isn't zero is written. So `set` reads the device's settings the Insteon device catalog gives a way to write, the same way `settings` reads them, just before the write and again once it's read back, and prints a line for each one whose value differs. A flag that's never written, such as one that turns the radio off, is compared too. A reading, or a value the catalog gives no way to write, such as a measure of noise, changes on its own rather than because of the write, so it isn't compared:

```
$ insteon device 4D.5E.6F set "linger time" 0x05
Linger time: 0x00 → 0x05
Also changed: Sparkle: off → on
```

Each Get Operating Flags request and extended Get the comparison needs is sent once before the write and once after it, and the write's own read and read-back count among them, since they carry the other settings that share their reply. A flag write's other requests are separate: Get Insteon Engine Version and, for a flag the catalog writes in an extended message while another flag is set, the read of that flag. A value write sends neither. Values are read for button 1 and, for a per-button setting, the button written, so a flag write or a write to button 1 compares button 1 only. The setting written is compared on the other button read, and a per-button setting is always named with its button. Nothing more is sent to a device whose catalog entry describes no other setting it gives a way to write, when the setting written is on button 1 or isn't per button. Nothing more is sent either when the device doesn't answer the write's own read, or when the write isn't confirmed. A setting the device didn't report before the write is left out; one it reported before but not after is named in a line that says it couldn't be read again, with the `settings` command that shows it. When none of the other settings can be read after the write, the write still succeeds, and the command says why and that what else it changed isn't known. With `--json`, `set` prints the setting's `name`, `label`, `button`, `before`, `requested` and `after`; `otherSettingsOutcome`, how the comparison ended (`compared`, `nothingToCompare`, `notReportedBefore`, `notConfirmed` or `notReread`); `rereadFailure` for `notReread` (`notAnswered`, `connectionClosed`, `canceled` or `failed`); `changedSettings`, each with its `name`, `label`, `button`, `before` and `after`; and `unreadSettings`, each with its `name`, `label` and `button`.

### Self-test

`insteon device ADDRESS selftest` checks a device in order, and says of each check whether it passed, warned, failed or was skipped, with what may put it right:

1. It answers Get Insteon Engine Version and accepts the modem. A device that doesn't, or that rejects the modem as an unlinked i2CS device does, fails, and the checks that need it to answer are skipped.
2. The Insteon device catalog describes the identity it reports to ID Request in this test. A device that reports none is tested without the catalog.
3. It reports the product key the catalog gives its product, in its answer to Product Data Request. The request is sent only when the catalog gives a key; the check is skipped for a product the catalog says reports none, or gives no key for. A different key, or none, warns with a catalog update. No answer warns with a second run when the catalog says a device was seen reporting its key; when the catalog knows the key from documents only, no answer skips the check, since the device may never send one. `device ADDRESS id` says the same of a key the device didn't report.
4. It reports its state, with the status request its catalog entry names.
5. Its ALL-Link database, read from the device, ends with the record that marks its end and, for an i2CS device, has every record's checksum intact; older devices send no checksums to check. A damaged record isn't taken for a missing link: the link checks then warn and ask for the test to run again.
6. It and the modem hold both records of each link the catalog gives the device to a Hub, or, for a device without those, of each link their records show. A link missing a record on one side works one way only. A link the catalog says covers every group the device controls while an operating flag is in a state gets a check for each of those groups in use, titled with the group's number and name. A group missing a record fails when it's the link's own group, or when the flag is in that state; it warns when the flag isn't, since the link then covers its own group alone, or when the flag couldn't be read.
7. Its records name only the modem and devices the modem is linked to; a record for any other device may be left from a device that's gone.
8. None of the operating flags the catalog guards locks it or cuts it off from the modem: a flag guarded as never set, such as one that locks linking from the device, is reported when it's on, with the `set` command that turns it off; a kept flag is reported only when the catalog gives its default, the state the device leaves the factory in, and the flag isn't in it. A kept flag with no default isn't reported, since either state may be the device's own. The flags that turn a device's radio or powerline off or require a checksum are reported once the catalog gives them a default of off.

It only reads, and writes no record and no setting. `--actuate` also sends Beep, when the device's catalog entry lists a Beep that's sent to it, and nothing to a device the catalog doesn't describe. `--checklist` also lists the checks only a person can do, once, after the others: pressing the device's button for each group it controls the modem with while `insteon watch` runs, and cutting its power for about ten seconds. With `--json` it prints the address, the engine, category, subcategory, firmware version and product as `device ADDRESS id --json` does, the `productKey` the device reported and the `catalogProductKey` as `device ADDRESS id --json` prints them, the outcome, each check's `id`, `title`, `group` and `groupName` where it's about a group, `outcome`, `detail` and `fixes`, each fix with a stable `id`, its `text` and, where it applies, `modemRole`, `group`, `addresses` or `setting`, and the `checklist`, each item with an `id`, its `group` where it applies, and its `text`.

### Writing ALL-Link databases

Linking with linking mode or the SET button stays the default. `insteon link ADDRESS --database` and `insteon unlink ADDRESS --database` write the records instead, for a device that answers the modem but doesn't link with linking mode, or whose links' other half is gone:

1. Both databases are read from the devices, and the command shows each write it plans: the records the catalog's links need and the databases lack, or, to unlink, the records of every link between the device and the modem. Records already there stay as they are.
2. A device's new record goes into its first free slot, then past its last record, which first writes the slot below as the new end of its database. No record in use is overwritten, and an unlinked record's slot is cleared, never compacted. A responder record holds the catalog's data bytes for the group, with full on as its on-level and 0.5 s as its ramp rate where the catalog gives no value.
3. It asks before writing, unless `--yes` or `--dry-run` is given, then reads both databases again and writes nothing if either changed.
4. Each write is read back, and made once more if it reads back differently; if it still does, or the device doesn't answer, the writes after it aren't made. Last, both databases are read again and every record is compared with what the writes should have left. The command fails when anything isn't as planned.

The device must run i2CS and accept the modem, as it does once it holds any record of the modem, or run i2 by the catalog. Nothing is written to an i1 device, to an i2CS device that rejects the modem, or when the device's database fails a checksum, has no end or has no room. An unlinked i2CS device rejects the modem once its last record of the modem is gone, so that write isn't read back. Nothing else is sent: no operating flag is written, and the relay isn't switched, even with `--relay-state`, which reads the flags the catalog names for how the relay holds a state as the plan is made; the plan says when one that keeps it from holding a state is on, since the relay then doesn't keep the state its record holds, and when every On and Off only pulses it. They aren't read again before the writes. `unlink --database` removes every link between the device and the modem, including links made before and the device's place in the modem's scenes, not only what `link --database` wrote; an i2CS device unlinked this way rejects the modem until it's linked again with linking mode or its SET button. Cleared orphans aren't restored, and an end of the database a link moved down stays. With `--json`, both print one object: the `direction`, `device`, `modem`, `engine` and `product`, `dryRun`, each write in `steps` with its `kind`, `record` and, once made, `outcome`, the records already in place, the `orphans`, and, once the writes are made, `mismatches`, `deviceCheck` and `complete`. With `--relay-state`, it also carries `relayState`, `relayData1`, `relayFlagsOn`, the names of those flags that read on, `relayHoldsState` and `relayIgnoresState`.

### Moving to another modem

Every linked device holds records that name its controller by the modem's address, and a modem's address can't be changed, so a new modem needs those records rewritten. `insteon backup FILE` keeps what's needed, and `insteon transfer plan FILE`, run with the new modem connected, says what moving the devices would take. The plan is a list of steps and writes nothing; every request the command sends is a read.

The plan swaps controllers. A record of a device's that names the old modem is rewritten in place to name the new modem, with the same role, group and data bytes, and the old modem's matching record is added to the new modem, so the new modem holds both halves of the link. A link the old modem or the device holds without the other half is dead, so it's left as it is and the plan says so. Links between two devices are never touched, and no step touches a device that isn't in the backup.

A device is rewritten from afar only when it runs i2 and the backup holds its whole ALL-Link database. A device that runs i1, which has no remote writes to its database, or i2CS, which rejects a modem it isn't linked to, one that didn't answer when it was backed up, and every device when the backup holds no ALL-Link database of the old modem, as a Hub Pro's doesn't, is listed with the links to make again and the steps by hand: the new modem's SET button, then the device's, in address order.

When the connected modem already holds links, the plan refuses to go on unless `--merge` keeps them and adds the backup's, or `--replace-database` removes them first as destructive steps. Each has its own warning. A Hub Pro can be the connected modem: its address comes from its device list, and its ALL-Link database isn't read, so the plan says it assumes none. `--json` prints the plan; the same backup and modem make the same bytes.

### Exploring

`device ADDRESS send` and `modem send` send what you give them, to learn what a device or modem does that the catalog doesn't describe yet, with exceptions that nothing forces. Set Operating Flags (`0x20`) with cmd2 `0x0C`, `0x0E`, `0x19` or `0x00`, which can cut a device off from the modem or lock it, depending on the device, goes only to a device the identity cache knows whose catalog entry names that cmd2 for a flag or command it doesn't guard, such as a keypad whose button lock is turned on with `0x19`. A cmd2 the catalog entry names for a guarded flag, or doesn't name at all, is refused: the refusal names the guarded flag by its label from the catalog entry, and otherwise says only what the protocol does. Poke (`0x29`), which writes a device's memory, its ALL-Link database included, is never sent; Set Address MSB (`0x28`) and Peek (`0x2B`) write nothing and are sent. `modem send` has no device to look up, so it refuses those four Set Operating Flags and Poke in any message to a device (`0x62`) or a group (`0x61`) it's given, and never writes such a message cut short. For a device the identity cache knows, `device ADDRESS send` also refuses a message its catalog entry never sends, and an extended message that writes a byte holding a flag the catalog guards, which only `device ADDRESS set` writes, once it has read the byte. To a device the identity cache doesn't know, or whose catalog entry gives no command set, it refuses an extended Set (`0x2E` with D2 other than `0x00`), and to any other device one whose selector its catalog entry doesn't list, since which bits it writes can't be told. Every command checks each byte an extended message writes the same way, whether `send`, `set` or an action such as `on` built it.

`modem send` also refuses, without `--force`, a command number the package doesn't know and commands that change or erase what the modem keeps or stop it answering, such as Reset the IM (`0x67`), Manage ALL-Link Record (`0x6F`) and Write Database (`0x76`). It also refuses Start ALL-Linking (`0x64`) with link code `0xFF`, which deletes links, and a message (`0x62`) that writes to a device, which `device ADDRESS set` and `device ADDRESS send` are for: Read/Write ALL-Link Database (`0x2F`), any other Set Operating Flags (`0x20`) and Extended Set/Get (`0x2E`) with D2 other than `0x00`. A command must have the length its number calls for, counting `0x02`: 8 bytes for a standard message and 22 for an extended one, and 2 or 3 for Beep (`0x77`). What you learn belongs in the catalog, marked as observed.

### Naming devices

The command names a device only from the identity it reported: its category, subcategory and firmware version, from an ID Request or from the modem's ALL-Linking Completed report. It never reads them from the data bytes of the modem's ALL-Link records, which don't hold them reliably. Identities that `link`, `links --identify`, `device ADDRESS id` and `watch` learn are kept in `$XDG_CACHE_HOME/insteon/identities.json`, or `~/.cache/insteon/identities.json`, readable only by you. `links`, `device ADDRESS links` and `device ADDRESS id` also keep in it the modem's and devices' ALL-Link databases, each device's engine, last level and the time it last answered, and the Hub's address, port and Insteon ID, so `device ADDRESS links` shows a device's ALL-Link database without reading it again while the device reports the same ALL-Link database delta. The file never holds the Hub's user name or password; delete it to forget what it holds. A file in a format the command doesn't read is left as it is, with one warning a run when an identity can't be remembered. A symbolic link at the file's path is left as it is too, with a warning, and is never replaced.

### Updating the catalog

The command names products and events from the Insteon device catalog. A copy ships in the bundle next to the command; `insteon catalog update` brings newer catalog data without another release of the package:

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

Other commands use the cached copy when it has the bundled copy's MAJOR.MINOR and a PATCH at least as high, and the bundled copy otherwise, such as after installing a newer release of the package. A cached copy that can't be read gets a one-line warning, and the bundled copy is used. A catalog published in a newer format needs a newer swift-insteon; `catalog update` says so and keeps the current copy. A published catalog older than the copy in use, or than the bundled copy, isn't downloaded, so a stale cache or a rolled-back site can't take back newer data; `catalog update` says so and keeps the current copy. A published or cached catalog isn't used when it would let more be sent or written to a device than the bundled copy does, at any firmware version, counting a device the bundled copy doesn't know as one with no command set, such as a flag that cuts a device off losing its `keep` guard: `catalog update` names what it weakens and keeps the current copy, replacing a cached copy that fails this check, and other commands warn and use the bundled copy. Without a readable bundled copy, a cached copy isn't used either.

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
Product:      Example Dimmer 9101 (DemoLinc Dimmer)

$ swift run insteon --hub 192.168.1.20 device 4D.5E.6F on 50%
Connecting to the Hub at 192.168.1.20:25105
Turned 4D.5E.6F on at 50%.
```

## Layout

- `Sources/insteon`: the command's front end. It holds the terminal (writing results and notes, asking yes-or-no questions, waiting for Return), Control-C and the exit status; the files and connections (the environment file, the modem or Hub, the identity cache and the two catalog copies on disk, and the catalog's site), which it passes to InsteonCLISupport; and the layout of reports that only arrange what a library returned: the tables of `info`, `links`, `device ADDRESS links`, `settings` and `discover`, `device ADDRESS status`, `ping`'s time, `watch`'s time stamps and the raw replies of `send`
- `Sources/InsteonCLISupport`: everything the command decides, as plain functions the tests in `Tests/InsteonCLISupportTests` cover, with the files, network and terminal passed in: reading the command line, finding and checking the environment file and reading its variables, choosing the modem and refusing a Hub that wouldn't be sent the password, where the identity cache is kept and how changes are merged into it, choosing between the bundled and cached catalogs and whether `catalog update` saves the published one, how `discover` searches and where it sends the password, what `device ADDRESS id` asks and prints, what the linking commands and `remove` save, ask and print for each step and when they fail, when `links` suggests `--identify`, the exit status for each error, and the text the command prints from the catalog

## Hub Pro

A host that answers as a Hub Pro is read and controlled through its local HTTP interface, which needs no user name or password and is never sent one. `insteon` asks it one request at a time, because a Hub Pro can stop answering under load. The Hub Pro decides which commands each device takes: a command it doesn't list for a device is refused before anything is sent, and the Insteon device catalog still decides what the device is and what its commands mean.

| Command | What it does on a Hub Pro |
| --- | --- |
| `info` | Prints the Hub Pro's configuration and server versions and the devices it lists, with the catalog's product for each. |
| `device ADDRESS id` | Prints what the Hub Pro reports for the device: its name, type, category, subcategory, firmware version, SKU, the catalog's product and the commands it lists. The engine is "not reported": a Hub Pro offers no way to read it. |
| `device ADDRESS status` | Reads the device's level with StatusRequest. |
| `device ADDRESS on [LEVEL%] [--fast]`, `off [--fast]` | On, Off, FastOn and FastOff, each only when the Hub Pro lists it for the device. A level is mapped to the Hub Pro's `OnLevel` scale, 0 through 255. |
| `device ADDRESS ping`, `beep` | Ping and Beep, each only when the Hub Pro lists it for the device. |
| `observe [--note TEXT] [--output PATH]` | Records the Hub Pro's versions, the kinds of device it lists and, for each device, its category, subcategory, firmware version, SKU and the names of the commands it lists, as `insteon-hubpro-observation/1` (`Schemas/insteon-hubpro-observation-1.schema.json`, with an example next to it). It sends only reads and no command, and the file holds no address, name or place; share it so the catalog can learn which firmware versions behave alike. |

A command the Hub Pro doesn't confirm may have reached the device: it is reported as such and never sent again. Everything else, such as `links`, `link`, `unlink`, `remove`, `scene`, `watch`, a device's settings and `modem send`, says a Hub Pro can't do it, before anything is sent. Add and remove devices with the Hub Pro's SET buttons, as its manual describes: `insteon` never asks a Hub Pro to add or remove a device, change a link or update, and sends none of the commands that write or clear a link.

A Hub Pro is recognized when `--hub` names a host, or a Hub file whose address is one, that answers as a Hub Pro, whether or not credentials are set. Its Hub file, `hubs/NAME.env`, needs only `INSTEON_HUB_HOST`: `insteon hubs` lists it and `insteon --hub NAME info` reaches it. The Hub Pro sends nothing on its own, so a change made at a device shows at the next read.
