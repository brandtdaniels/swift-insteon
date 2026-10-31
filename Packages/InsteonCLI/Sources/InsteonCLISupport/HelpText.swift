/// The `insteon` command's help: an overview, and a page for each subcommand.
public enum HelpText {

  /// The help for a subcommand, or the overview.
  ///
  /// - Parameter topic: A subcommand's name, or `nil` for the overview.
  /// - Returns: The help, or `nil` if `topic` isn't a subcommand.
  public static func text(for topic: String?) -> String? {

    guard let topic else {

      return overview

    }

    return switch topic {
    case "discover": discover
    case "info": info
    case "links": links
    case "link": link
    case "unlink": unlink
    case "remove": remove
    case "device": device
    case "scene", "group": scene
    case "beep": beep
    case "modem": modem
    case "watch": watch
    case "catalog": catalog
    default: nil
    }

  }

  /// The overview: the command's usage, options, subcommands and environment.
  public static let overview = """
    Drive an Insteon Hub or modem, and its devices, from the terminal.

    Usage: insteon [--hub HOST[:PORT] | --serial PATH] [--env-file PATH] [--json] COMMAND [OPTIONS]

    Commands:
      discover            Find Hubs on the local network
      info                Show the modem's Insteon ID, identity and product
      links               List the modem's ALL-Link database
      link [ADDRESS]      Link a device to the modem, by its address or its SET button
      unlink [ADDRESS]    Unlink a device from the modem, with its SET button or, with
                          --all, by its address
      remove ADDRESS      Remove a device from the network: unlink it from the modem,
                          forget it and show its factory reset steps
      device ADDRESS ...  Control a device, read and change its settings, or read its
                          ALL-Link database
      scene GROUP on|off  Turn the devices in one of the modem's groups on or off
      beep [--double]     Make the modem beep
      modem send HEX      Send the modem a serial command as given, for exploring
      watch               Print what the modem hears until Control-C
      catalog [update]    Show the Insteon device catalog's version, or download the latest
                          compatible one

    Options:
      --hub HOST[:PORT]   The Hub to use. Defaults to INSTEON_HUB_HOST and INSTEON_HUB_PORT.
      --serial PATH       A modem on a serial or USB port, such as /dev/ttyUSB0 (macOS and Linux).
      --env-file PATH     Read environment variables from PATH instead of the default file.
      --json              Print JSON, where the command supports it.
      -h, --help          Show help. 'insteon COMMAND --help' shows a command's help.

    Environment:
      INSTEON_HUB_USERNAME, INSTEON_HUB_PASSWORD
                          The user name and password printed on the Hub. They're read only
                          from the environment or the environment file, never from the
                          command line.
      INSTEON_HUB_HOST, INSTEON_HUB_PORT
                          The Hub to use when --hub isn't given.

    Environment file:
      $XDG_CONFIG_HOME/insteon/env, or ~/.config/insteon/env, or the file --env-file names,
      holds KEY=VALUE lines, such as INSTEON_HUB_PASSWORD=..., for the variables above. A
      variable set in the environment wins over the file. The file must belong to you and be
      writable only by you; make it readable only by you with 'chmod 600'. It's never read
      from the current directory.

    Files:
      $XDG_CACHE_HOME/insteon/identities.json, or ~/.cache/insteon/identities.json, keeps the
      identities devices reported to 'link', 'links --identify' and 'device ADDRESS id', so
      later commands can name them. 'links', 'device ADDRESS links' and 'device ADDRESS id'
      also keep in it the modem's and devices' ALL-Link databases, each device's engine, last
      level and the time it last answered, and the Hub's address, port and Insteon ID. It
      never holds the Hub's user name or password.
      $XDG_CACHE_HOME/insteon/catalog.json, or ~/.cache/insteon/catalog.json, with
      catalog-version.json beside it, is the Insteon device catalog 'catalog update'
      downloaded. It holds only the public catalog.

    Example:
      insteon --hub 192.168.1.20 info
    """

  /// The help for `insteon discover`.
  public static let discover = """
    Usage: insteon discover [--local] [--insteon-connect] [--all]
                            [--identify [HOST[:PORT]]] [--json]

    Finds Hubs in two ways. Only the local network is searched unless --insteon-connect is
    given; give both options for both ways.
      --local             Ask the addresses on the local private subnets for a Hub's page,
                          without credentials, stopping at the first Hub. Results are
                          candidates: check the address before sending a password there.
                          The default.
      --all               Ask every address on the local network, rather than stopping at
                          the first Hub.
      --insteon-connect   Ask Insteon Connect, which lists the Hubs that reported from this
                          network in the past 24 hours, with their Insteon IDs and models.
                          This shares the network's public IP address with Insteon.
      --identify          Ask Hubs found at a private address for Get IM Info, with the
                          configured INSTEON_HUB_USERNAME and INSTEON_HUB_PASSWORD, to show
                          their Insteon IDs and models. This sends the password, unencrypted,
                          so the command asks before sending it to each Hub found on port
                          25105, and stops at the first Hub that rejects it. Without a
                          terminal to ask at, name the one Hub instead.
      --identify HOST[:PORT]
                          Ask only the Hub found at HOST, on PORT or port 25105, without
                          asking first.
    """

  /// The help for `insteon info`.
  public static let info = """
    Usage: insteon [--hub HOST[:PORT] | --serial PATH] info [--json]

    Asks the modem about itself with Get IM Info: its Insteon ID, category, subcategory and
    firmware version, and the product the Insteon device catalog has for them.
    """

  /// The help for `insteon links`.
  public static let links = """
    Usage: insteon [--hub HOST[:PORT] | --serial PATH] links [--identify] [--json]

    Reads the modem's whole ALL-Link database and lists each record: whether the modem
    controls the device or responds to it, the group, the device's address, the three data
    bytes, and the product the Insteon device catalog has for the device when its identity
    is known. Identities come from 'link' and 'device ADDRESS id', never from the records'
    data bytes.

      --identify          Ask each linked device for its identity with ID Request, one
                          request per device.
    """

  /// The help for `insteon link`.
  public static let link = """
    Usage: insteon [--hub HOST[:PORT] | --serial PATH] link [ADDRESS] [--group N]
                   [--controller | --responder | --either] [--two-way | --one-way]
                   [--timeout SECONDS] [--json]
           insteon [--hub HOST[:PORT] | --serial PATH] link --cancel

    With ADDRESS, the device's Insteon address from its label, links the device without its
    SET button: the modem starts ALL-Linking and sends the device Enter Linking Mode. A device
    the command hasn't identified is asked for its identity with ID Request first, so the
    Insteon device catalog can say how to link it; one that doesn't answer, as an i2CS device
    may not until it's linked, is linked as a device the catalog doesn't describe. When the
    catalog gives the device's links to a Hub, and no --group, --responder, --either,
    --two-way or --one-way is given, the command makes those links in the catalog's order,
    one at a time: the modem starts ALL-Linking in each link's role and group, and the device
    joins with Enter Linking Mode, or with its SET button where the catalog says so. When
    the modem is the controller and the Insteon device catalog says the device is a light or
    switched load, it's first turned fully on with Light On, so it links with full on as its
    on-level; any other device, such as an I/O module or a lock, links with whatever on-level
    it captures. If the device doesn't answer, as an i2CS device may not until it's linked,
    the command falls back to its SET button.

    Without ADDRESS, puts the modem into linking mode with Start ALL-Linking, then waits for
    someone to press and hold a device's SET button, and prints the linked device.

    Either way, when the modem is the controller and the catalog says the device can
    control, the device is then linked back without a second SET press, with the modem as
    its responder, so the modem hears the device's buttons. It's linked back in the first
    group the catalog says it controls, group 1 when it controls that.

      --group N           The modem's ALL-Link group, from 0 to 254. Defaults to 0, as
                          Insteon's Hub app links devices.
      --controller        The modem controls the device. The default.
      --responder         The modem responds to the device, which is the controller, so it
                          goes into linking mode first: the command says how, and waits for
                          Return before starting the modem. With ADDRESS, the modem joins the
                          device's group a link back uses, not the --group one.
      --either            The modem controls the device or responds to it, as the device asks.
      --two-way           Link the device back even when the catalog doesn't say it can
                          control, or doesn't have it.
      --one-way           Don't link the device back: the modem only controls it.
      --timeout SECONDS   How long to wait for the SET button. Defaults to 240, the time the
                          modem stays in linking mode.
      --cancel            Take the modem out of linking mode with Cancel ALL-Linking.

    With --json, prints one object, the same for every device: "links", every link the modem
    reported, in order, and "legs", each of the catalog's links to a Hub with its modemRole,
    modemGroup, deviceGroup, status (linked, failed or notRun), joinedBy and error, or an
    empty array when the device wasn't linked by them.

    Control-C stops waiting and takes the modem out of linking mode.
    """

  /// The help for `insteon unlink`.
  public static let unlink = """
    Usage: insteon [--hub HOST[:PORT] | --serial PATH] unlink [ADDRESS] [--group N]
                   [--controller | --responder] [--timeout SECONDS] [--json]
           insteon [--hub HOST[:PORT] | --serial PATH] unlink ADDRESS --all
                   [--timeout SECONDS] [--json]

    Removes a link with a device's SET button and prints the unlinked device. With ADDRESS,
    only that device's unlink is accepted, and its own steps are shown when its identity is
    known. Afterward, it says which groups still link the device.

    With ADDRESS and --all, removes every link between the modem and the device, in every
    group the modem's ALL-Link database has for it and in both directions, without its SET
    button: for a link the device controls, the device is sent Enter Unlinking Mode and the
    modem joins as responder; for a link in one of the modem's groups, the modem starts
    ALL-Linking in unlinking mode and the device is sent Enter Linking Mode. If that fails,
    the command says which links are left and how to remove them with the SET button.

      --group N           The modem's ALL-Link group in the link, from 0 to 254. With
                          ADDRESS, defaults to the group the modem's records for the device
                          show; links made before group 0 became the default are in group
                          1. Otherwise defaults to 0.
      --controller        The modem controls the device: the modem enters unlinking mode,
                          then the device's SET button is pressed. The default.
      --responder         The modem responds to the device, which is the controller, so it
                          goes into unlinking mode first: the command says how, and waits
                          for Return before the modem joins.
      --all               Remove every link with ADDRESS without its SET button, as above.
                          Not with --group, --controller or --responder.
      --timeout SECONDS   How long to wait. Defaults to 240, or with --all, 30 for each
                          link.
    """

  /// The help for `insteon remove`.
  public static let remove = """
    Usage: insteon [--hub HOST[:PORT] | --serial PATH] remove ADDRESS [--scan]
                   [--force-modem-side] [--yes] [--timeout SECONDS] [--json]

    Removes a device from the network. First it removes every link between the modem and the
    device without its SET button, as 'unlink ADDRESS --all' does: the links the device
    controls first, and the modem's group 0 last. Once the modem's ALL-Link database, read
    again, has no links with the device, the identity cache forgets it: its identity, its
    state and the modem's records for it. Last, it shows the Insteon device catalog's steps
    to restore the device's factory settings, which erases the links the device itself
    keeps; the command never resets a device.

    If a link can't be removed that way, or the modem still has links with the device, the
    command says which and how to remove them, keeps the device, and fails.

    It asks before it starts. Without a terminal to ask at, it needs --yes.

      --scan              Also read the ALL-Link databases of the other devices the identity
                          cache knows, and list each record that still names the device, such
                          as a scene's. Those records are only listed, never changed.
      --force-modem-side  For a device that's gone, such as one thrown away or one whose
                          batteries are dead: when its links can't be removed through it,
                          or the modem still has links with it, delete the modem's records
                          for it directly with Manage ALL-Link Record, list them, and remove
                          it once none are left. The device's own records stay, so only use
                          it for a device that won't come back.
      -y, --yes           Don't ask first.
      --timeout SECONDS   How long to wait for each link to be removed. Defaults to 30.

    'unlink ADDRESS --all' removes the links and keeps the device in the identity cache.
    """

  /// The help for `insteon device`.
  public static let device = """
    Usage: insteon [--hub HOST[:PORT] | --serial PATH] device ADDRESS ACTION [--json]

    ADDRESS is the device's Insteon address, such as 1A.2B.3C, printed on it.

    Actions:
      id                  Ask for the device's engine (Get Insteon Engine Version), its
                          category and subcategory (ID Request) and its product data (Product
                          Data Request), and show the product the Insteon device catalog has.
      ping                Check that the device answers (Ping).
      on [LEVEL] [--fast] Turn the device on (Light On), fully or to LEVEL percent, such as 50%.
                          A device the Insteon device catalog says is on/off only turns on.
                          --fast ignores the ramp rate (Light On Fast), and needs the
                          device's catalog entry to list it, when there is one.
      off [--fast]        Turn the device off (Light Off, or Light Off Fast).
      instant LEVEL       Change the device to LEVEL percent at once (Light Instant Change).
                          An on/off device turns on, or off for 0%.
      status              Ask for the device's state with the command its main group's type
                          in the catalog names, and read it as the type says: a level for a
                          dimmer, on or off for a device that's on/off only, or the name the
                          catalog gives the value. Any other device is asked with Light
                          Status Request.
      beep                Make the device beep (Beep). It's sent even when the catalog doesn't
                          list Beep for the device, with a note saying so.
      links               Read the device's ALL-Link database, with what each record's data
                          means when the device is known.
      settings [--advanced]
                          Read the settings the Insteon device catalog describes for the
                          device: its operating flags (Get Operating Flags), its values
                          (extended Get, for each button where they're per button) and its
                          readings, grouped by section, with defaults and which can be
                          changed. --advanced also shows settings such as the powerline's
                          timing and X10.
      set NAME VALUE [--button N]
                          Change a setting, named as 'settings' shows it or by its catalog
                          name, such as rampRate. VALUE is on or off for a flag, a label such
                          as 0.5s, a number in the setting's unit such as 50%, or a byte such
                          as 0x1C. --button picks the button or group of a per-button
                          setting; it defaults to 1. The setting is read back afterward.
                          Turning off the radio or the powerline, and requiring a checksum,
                          are never written, and the programming lock is only turned off,
                          also through a value whose byte holds them.
      send CMD1 CMD2 [--extended [D1 ... D14]] [--no-checksum] [--wait SECONDS]
                          Send the device a direct message as given, for exploring, and print
                          its ACK or NAK and the messages it sends in the next SECONDS,
                          3 by default. Bytes are hexadecimal, such as 0x2E or 2E. With
                          --extended, the message is extended, with the data bytes given and
                          0x00 after; unless all 14 are given or --no-checksum is, D14 holds
                          the checksum i2CS devices require.

    'on', 'off', 'instant', 'status', 'beep', 'links', 'settings' and 'set' use the device's
    identity, from the identity cache or, for a device the cache doesn't know, an ID Request
    sent first, to look it up in the Insteon device catalog. 'on' and 'off' refuse a device
    that doesn't report its identity; 'beep' is sent anyway. What 'send' finds is worth adding
    to the catalog, marked as observed.
    """

  /// The help for `insteon scene`.
  public static let scene = """
    Usage: insteon [--hub HOST[:PORT] | --serial PATH] scene GROUP on|off
           insteon [--hub HOST[:PORT] | --serial PATH] group GROUP on|off

    Sends Light On or Light Off to one of the modem's ALL-Link groups, from 0 to 254, with
    Send ALL-Link Command: the modem broadcasts it, then sends each device that responds to
    the group a cleanup message. Says how many responders the modem's ALL-Link database
    lists for the group, and which didn't acknowledge their cleanup.
    """

  /// The help for `insteon beep`.
  public static let beep = """
    Usage: insteon [--hub HOST[:PORT] | --serial PATH] beep [--double]

    Makes the modem beep (Beep). --double beeps twice, which only later modem firmware does.
    """

  /// The help for `insteon modem`.
  public static let modem = """
    Usage: insteon [--hub HOST[:PORT] | --serial PATH] modem send HEX [--force] [--wait SECONDS]

    Writes a serial command to the modem as given, for exploring, then prints everything the
    modem sends in the next SECONDS, 3 by default, in hexadecimal and as the package reads it.
    HEX is the command's bytes, starting with 02, such as 0277 or 02 77 01.

    Without --force, a command is refused when the package doesn't know its number, since the
    modem's answer can't be read, or when it changes or erases what the modem keeps or stops
    it answering, such as Reset the IM (0x67), Manage ALL-Link Record (0x6F) and Write
    Database (0x76). So is Start ALL-Linking (0x64) with link code FF, which deletes links,
    and a message (0x62) that writes to a device: Read/Write ALL-Link Database (0x2F), Set
    Operating Flags (0x20) or Extended Set/Get (0x2E) with D2 other than 00. Use 'insteon
    device ADDRESS set' or 'insteon device ADDRESS send' for those. A command must also have
    the length its number calls for, counting 02: 8 bytes for a standard message and 22 for
    an extended one, and 2 or 3 for Beep (0x77).

    What you find is worth adding to the Insteon device catalog, marked as observed.

      --force             Send the command even so.
      --wait SECONDS      How long to print the modem's replies. Defaults to 3.
    """

  /// The help for `insteon watch`.
  public static let watch = """
    Usage: insteon [--hub HOST[:PORT] | --serial PATH] watch [--raw]

    Prints what the modem hears until Control-C: devices' group commands, read as named
    events, such as a leak sensor's wet, when the Insteon device catalog knows the device,
    and other messages as they are. A device is known when an earlier command learned its
    identity, or when it reports one, such as when its SET button is pressed; the identities
    devices report are kept in the identity cache.

    Only messages sent to the modem, and group broadcasts from devices it has responder
    records for, reach it. To hear a device's buttons, link the modem as its responder
    with 'insteon link --responder' or 'insteon link ADDRESS --two-way'.

      --raw               Also print each message's bytes as the modem sent them, such as
                          0250 1A2B3C 012041 8F 01 00.
    """

  /// The help for `insteon catalog`.
  public static let catalog = """
    Usage: insteon catalog
           insteon catalog update

    The command names products and events from the Insteon device catalog. A copy ships
    next to the command; 'catalog update' keeps a newer one in
    $XDG_CACHE_HOME/insteon/catalog.json, or ~/.cache/insteon/catalog.json.

    'insteon catalog' prints the bundled copy's version, the cached copy's, or none, and
    which one is in use. The cached copy is used when it's in the format the command reads,
    the same MAJOR.MINOR as the bundled copy, and at least as new.

    'insteon catalog update' downloads the latest published catalog over HTTPS from
    https://brandtdaniels.github.io/insteon-device-catalog/v0/, when it's in the format the
    command reads and differs from the copy in use, and checks its SHA-256 before saving
    it. It needs no Hub or modem, reads no Hub settings, and sends nothing but the requests
    for the catalog. A catalog in a newer format needs a newer swift-insteon; the current
    copy stays until then.
    """

}
