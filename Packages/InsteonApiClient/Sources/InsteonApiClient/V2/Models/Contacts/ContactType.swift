public enum ContactType: String {

  case email

  case sms = "SMS"

  case pushNotification = "PNS"

}

// MARK: - Codable

extension ContactType: Codable {}
