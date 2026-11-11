import InsteonDeviceCatalog

/// What an operation lets InsteonCore send for it: the effects it grants, and whether it grants
/// a message no catalog entry describes.
///
/// A message that only asks for state, ``CommandEffect/readOnly``, needs no consent, so
/// ``effects`` doesn't have to list it. An operation that names the act, such as turning a
/// device on, grants just the effect of that act:
///
/// ```swift
/// let turnOn = SendConsent(effects: [.actuation])
/// ```
public struct SendConsent: Hashable, Sendable {

  /// The effects the operation grants. An effect this package doesn't know grants nothing,
  /// since a message with one is ``CommandEffect/destructive``.
  public var effects: Set<CommandEffect>

  /// Whether the operation grants a message no entry of the device's command set describes,
  /// such as bytes a person types for a raw send.
  public var allowsUndescribed: Bool

  /// Creates a consent.
  ///
  /// - Parameters:
  ///   - effects: The effects the operation grants. Defaults to none.
  ///   - allowsUndescribed: Whether it grants a message no command set entry describes.
  ///     Defaults to `false`.
  public init(effects: Set<CommandEffect> = [], allowsUndescribed: Bool = false) {

    self.effects = effects
    self.allowsUndescribed = allowsUndescribed

  }

}

/// What InsteonCore does with a message: send it, ask for more consent, or refuse it.
public enum SendDecision: Hashable, Sendable {

  /// The message is sent.
  case transmit

  /// The operation doesn't grant what the message does, so nothing is sent until it does. The
  /// associated value is the effect the message needs granted, or `nil` for a message no
  /// entry describes.
  case needsConsent(CommandEffect?)

  /// The message is never sent, whatever the operation grants.
  case refuse(SendRefusal)

}

/// The one place that decides whether a message is sent, from what it does and what the
/// operation grants.
///
/// The decision is a pure function, in this order, and the first rule that applies decides:
/// 1. A refusal the byte floor or a guard already made refuses the message, whatever the
///    consent.
/// 2. An effect that's missing or that this package doesn't know is
///    ``CommandEffect/destructive``.
/// 3. A message no entry describes needs ``SendConsent/allowsUndescribed``.
/// 4. A ``CommandEffect/readOnly`` message is sent.
/// 5. An effect in ``SendConsent/effects`` is sent.
/// 6. Any other effect needs consent.
///
/// ```swift
/// let decision = SendPolicy.decision(effect: .configuration, consent: SendConsent(effects: [.actuation]))
/// // needsConsent(configuration)
/// ```
public enum SendPolicy {

  /// Decides what to do with a message.
  ///
  /// - Parameters:
  ///   - effect: What the device's command set says the message does, or `nil` if no entry
  ///     describes it.
  ///   - declaredEffect: What the flow that builds the message says it does, or `nil` if it
  ///     declares none. The stricter of the two decides; two different effects of equal rank
  ///     read as ``CommandEffect/destructive``.
  ///   - refusal: Why a guard or the byte floor refuses the message, or `nil` if neither does.
  ///   - consent: What the operation grants.
  /// - Returns: The decision.
  public static func decision(effect: CommandEffect?, declaredEffect: CommandEffect? = nil, refusal: SendRefusal? = nil, consent: SendConsent) -> SendDecision {

    if let refusal {

      return .refuse(refusal)

    }

    let known: [CommandEffect] = [effect, declaredEffect].compactMap { (effect: CommandEffect?) -> CommandEffect? in

      effect.map(reading)

    }

    guard let first = known.first else {

      return consent.allowsUndescribed ? .transmit : .needsConsent(nil)

    }

    let combined: CommandEffect = known.dropFirst().reduce(first, stricter)

    if combined.strictness == .readOnly || consent.effects.contains(combined) {

      return .transmit

    }

    return .needsConsent(combined)

  }

  /// An effect as the policy reads it: one this package doesn't know is destructive.
  private static func reading(_ effect: CommandEffect) -> CommandEffect {

    effect.strictness == .destructive ? .destructive : effect

  }

  /// The stricter of two known effects, or destructive for two different ones of the same
  /// strictness.
  private static func stricter(_ left: CommandEffect, _ right: CommandEffect) -> CommandEffect {

    if left.strictness != right.strictness {

      return left.strictness > right.strictness ? left : right

    }

    return left == right ? left : .destructive

  }

}
