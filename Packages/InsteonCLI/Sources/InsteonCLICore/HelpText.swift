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
    case "device": device
    case "watch": watch
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
      unlink [ADDRESS]    Unlink a device from the modem with its SET button
      device ADDRESS ...  Control a device or read its ALL-Link database
      watch               Print what the modem hears until Control-C

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
      later commands can name them. It holds only Insteon addresses and identities.

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
                   [--controller | --responder | --either] [--two-way] [--timeout SECONDS] [--json]
           insteon [--hub HOST[:PORT] | --serial PATH] link --cancel

    With ADDRESS, the device's Insteon address from its label, links the device without its
    SET button: the modem starts ALL-Linking and sends the device Enter Linking Mode. If the
    device doesn't answer, as an i2CS device may not until it's linked, the command falls
    back to its SET button. A device the Insteon device catalog says can control is then
    linked back, with the modem as its responder.

    Without ADDRESS, puts the modem into linking mode with Start ALL-Linking, then waits for
    someone to press and hold a device's SET button, and prints the linked device.

      --group N           The modem's ALL-Link group, from 0 to 254. Defaults to 0, as
                          Insteon's Hub app links devices.
      --controller        The modem controls the device. The default.
      --responder         The modem responds to the device, which is the controller, so it
                          goes into linking mode first: the command says how, and waits for
                          Return before starting the modem.
      --either            The modem controls the device or responds to it, as the device asks.
      --two-way           Link the modem as controller, then as the device's responder, by
                          sending the device Enter Linking Mode, with no second SET press.
      --timeout SECONDS   How long to wait for the SET button. Defaults to 240, the time the
                          modem stays in linking mode.
      --cancel            Take the modem out of linking mode with Cancel ALL-Linking.

    Control-C stops waiting and takes the modem out of linking mode.
    """

  /// The help for `insteon unlink`.
  public static let unlink = """
    Usage: insteon [--hub HOST[:PORT] | --serial PATH] unlink [ADDRESS] [--group N]
                   [--controller | --responder] [--timeout SECONDS] [--json]

    Removes a link with a device's SET button and prints the unlinked device. With ADDRESS,
    only that device's unlink is accepted, and its own steps are shown when its identity is
    known. Afterward, it says which groups still link the device.

      --group N           The modem's ALL-Link group in the link, from 0 to 254. With
                          ADDRESS, defaults to the group the modem's records for the device
                          show; links made before group 0 became the default are in group
                          1. Otherwise defaults to 0.
      --controller        The modem controls the device: the modem enters unlinking mode,
                          then the device's SET button is pressed. The default.
      --responder         The modem responds to the device, which is the controller, so it
                          goes into unlinking mode first: the command says how, and waits
                          for Return before the modem joins.
      --timeout SECONDS   How long to wait. Defaults to 240.
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
      on [LEVEL]          Turn the device on (Light On), fully or to LEVEL percent, such as 50%.
                          A device the Insteon device catalog says is on/off only turns on.
      off                 Turn the device off (Light Off).
      status              Ask for the device's level (Light Status Request); on or off for a
                          device that's on/off only.
      links               Read the device's ALL-Link database, with what each record's data
                          means when the device is known.

    'on LEVEL', 'status' and 'links' use the device's identity, from the identity cache or
    an ID Request, to look it up in the Insteon device catalog.
    """

  /// The help for `insteon watch`.
  public static let watch = """
    Usage: insteon [--hub HOST[:PORT] | --serial PATH] watch [--raw]

    Prints what the modem hears until Control-C: devices' group commands, read as named
    events, such as a leak sensor's wet, when the Insteon device catalog knows the device,
    and other messages as they are. A device becomes known when it reports its identity,
    such as when its SET button is pressed.

    Only messages sent to the modem, and group broadcasts from devices it has responder
    records for, reach it. To hear a device's buttons, link the modem as its responder
    with 'insteon link --responder' or 'insteon link ADDRESS --two-way'.

      --raw               Also print each message's bytes as the modem sent them, such as
                          0250 1A2B3C 012041 8F 01 00.
    """

}
