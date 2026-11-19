import Foundation

/// Mutants aimed at `check-credentials`: interpolations of names that are and aren't credentials'.
public enum CredentialsMutations {
  static let snippets = [
    "\"\\(password)\"", "\"\\(hub.password)\"", "\"x \\(user):\\(password) y\"", "\"\\(tokenizer)\"", "\"\\(apiKey)\"",
    "\"\\(APIKey)\"", "\"\\(api_key)\"", "\"\\(privateKey) \\(accessKey)\"", "\"\\(private)\"", "\"\\(key)\"",
    "\"\\(env[\"INSTEON_PASSWORD\"] ?? \"\")\"", "\"\\(env[\"HOST\"] ?? \"\")\"", "\"\\(\"nested \\(bearerToken)\")\"",
    "\"\\(f(\"x\\(secret)\"))\"", "#\"\\#(token)\"#", "#\"\\(token)\"#", "##\"\\##(token)\"##", "\"\\(passwordPrompt)\"",
    "\"\\(userPwd)\" + \"\\(creds)\"", "\"\\(credential.value)\"", "\"\\(Secrets.clientSecret)\"", "\"\\(x\u{301}password)\"",
    "\"\\(a\u{E9}token)\"", "\"\\(\u{E9}token)\"", "\"\\(token", "\"\\(f(", "\"\\(g(1)\" token", "\"password \\(x)\"", "\"\\(x) token\"",
    "\"\\(authorizationHeader)\"", "\"\\(Authorization)\"", "\"\\(bearer)\"", "\"\\(BEARER_TOKEN)\"", "\"\\(passphrase)\"",
    "\"\\(a1token)\"", "\"\\(token2)\"", "\"\\(_token)\"", "\"\\(token_)\"", "\"\\(0token)\"", "\"\\(passwordToken)\""
  ]

  public static let sourceOperators: [TextOperator] = [
    CodeMutations.insertSnippet(from: snippets),
    CodeMutations.appendSnippet(from: snippets)
  ] + CommonOperators.all

  public static let allowListOperators = CodeMutations.allowListOperators(
    columns: 3,
    samples: [
      ["InsteonNetworking/Sources/InsteonNetworking/BasicAuthenticationHTTPClient.swift", "password", "Builds the header."],
      ["Nope/Sources/N.swift", "apiKey,token", "x"],
      ["Nope/Sources/N.swift", "token", "y"]
    ]
  ) + CommonOperators.all
}
