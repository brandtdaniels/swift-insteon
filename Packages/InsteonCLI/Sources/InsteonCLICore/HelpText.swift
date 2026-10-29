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

    Usage: insteon [--hub HOST[:PORT] | --serial PATH] [--json] COMMAND [OPTIONS]

    Commands:
      discover            Find Hubs on the local network
      info                Show the modem's Insteon ID, identity and product
      links               List the modem's ALL-Link database
      link                Link a device to the modem with its SET button
      unlink              Unlink a device from the modem with its SET button
      device ADDRESS ...  Control a device or read its ALL-Link database
      watch               Print what the modem hears until Control-C

    Options:
      --hub HOST[:PORT]   The Hub to use. Defaults to INSTEON_HUB_HOST and INSTEON_HUB_PORT.
      --serial PATH       A modem on a serial or USB port, such as /dev/ttyUSB0 (macOS and Linux).
      --json              Print JSON, where the command supports it.
      -h, --help          Show help. 'insteon COMMAND --help' shows a command's help.

    Environment:
      INSTEON_HUB_USERNAME, INSTEON_HUB_PASSWORD
                          The user name and password printed on the Hub. They're read only
                          from the environment, or from a .env file in the current directory,
                          never from the command line.
      INSTEON_HUB_HOST, INSTEON_HUB_PORT
                          The Hub to use when --hub isn't given.

    Example:
      insteon --hub 192.168.1.20 info
    """

  /// The help for `insteon discover`.
  public static let discover = """
    Usage: insteon discover [--local] [--insteon-connect] [--json]

    Finds Hubs in two ways, both by default:
      --local             Ask every address on the local private subnets for a Hub's page,
                          without credentials. Results are candidates: check the address
                          before sending a password there.
      --insteon-connect   Ask Insteon Connect, which lists the Hubs that reported from this
                          network in the past 24 hours, with their Insteon IDs. Insteon sees
                          this network's public IP address.
    """

  /// The help for `insteon info`.
  public static let info = """
    Usage: insteon [--hub HOST[:PORT] | --serial PATH] info [--json]

    Asks the modem about itself with Get IM Info: its Insteon ID, category, subcategory and
    firmware version, and the product the Insteon device catalog has for them.
    """

  /// The help for `insteon links`.
  public static let links = """
    Usage: insteon [--hub HOST[:PORT] | --serial PATH] links [--json]

    Reads the modem's whole ALL-Link database and lists each record: whether the modem
    controls the device or responds to it, the group, the device's address, the three data
    bytes, and the product the Insteon device catalog has for the device, when a controller
    record gives its category and subcategory.
    """

  /// The help for `insteon link`.
  public static let link = """
    Usage: insteon [--hub HOST[:PORT] | --serial PATH] link [--group N]
                   [--controller | --responder | --either] [--timeout SECONDS] [--json]
           insteon [--hub HOST[:PORT] | --serial PATH] link --cancel

    Puts the modem into linking mode with Start ALL-Linking, then waits for someone to press
    and hold a device's SET button, and prints the linked device.

      --group N           The modem's ALL-Link group, from 0 to 255. Defaults to 1.
      --controller        The modem controls the device. The default.
      --responder         The modem responds to the device. Put the device into linking mode
                          with its SET button first.
      --either            The modem controls the device or responds to it, as the device asks.
      --timeout SECONDS   How long to wait. Defaults to 240, the time the modem stays in
                          linking mode.
      --cancel            Take the modem out of linking mode with Cancel ALL-Linking.

    Control-C stops waiting and takes the modem out of linking mode.
    """

  /// The help for `insteon unlink`.
  public static let unlink = """
    Usage: insteon [--hub HOST[:PORT] | --serial PATH] unlink [--group N]
                   [--controller | --responder] [--timeout SECONDS] [--json]

    Puts the modem into unlinking mode with Start ALL-Linking, then waits for someone to
    press and hold a device's SET button, and prints the unlinked device.

      --group N           The modem's ALL-Link group in the link, from 0 to 255. Defaults to 1.
      --controller        The modem controls the device. The default.
      --responder         The modem responds to the device. Put the device into unlinking
                          mode with its SET button first.
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
      off                 Turn the device off (Light Off).
      status              Ask for the device's level (Light Status Request).
      links               Read the device's ALL-Link database.
    """

  /// The help for `insteon watch`.
  public static let watch = """
    Usage: insteon [--hub HOST[:PORT] | --serial PATH] watch [--raw]

    Prints what the modem hears until Control-C: devices' group commands, read as named
    events, such as a leak sensor's wet, when the Insteon device catalog knows the device,
    and other messages as they are. A device becomes known when it reports its identity,
    such as when its SET button is pressed.

      --raw               Also print every reply the modem sends, as it is.
    """

}
