import InsteonCore

/// What `insteon transfer verify` prints.
public enum TransferVerifyText {

  /// A table of each device and whether it answered, with its header.
  ///
  /// - Parameter verification: The result.
  /// - Returns: The rows.
  public static func rows(_ verification: TransferVerification) -> [[String]] {

    [["ADDRESS", "NAME", "RESULT"]] + verification.checks.map { (check: TransferDeviceCheck) -> [String] in

      [check.address.description, check.name ?? "-", check.answered ? "answered" : (check.problem ?? "didn't answer")]

    }

  }

  /// The sentence that says how many devices answered.
  ///
  /// - Parameter verification: The result.
  /// - Returns: The sentence.
  public static func summary(_ verification: TransferVerification) -> String {

    let total: Int = verification.checks.count
    let answered: Int = verification.checks.filter(\.answered).count

    if total == 0 {

      return "The backup holds no devices, so there is nothing to ask."

    }

    if answered == total {

      return "All \(total) \(total == 1 ? "device" : "devices") answered."

    }

    return "\(answered) of \(total) devices answered. Link the others by hand, as the plan lists, and run this again."

  }

}
