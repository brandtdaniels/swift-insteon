import Testing
import InsteonCLICore

struct DotEnvTests {

  @Test func readsKeysAndValues() throws {

    let variables = try DotEnv.parse("""
      # The Hub's credentials, printed on it.
      INSTEON_HUB_USERNAME=example-user

      INSTEON_HUB_PASSWORD = example-password
      export INSTEON_HUB_HOST=192.168.1.20
      """)

    #expect(variables == [
      "INSTEON_HUB_USERNAME": "example-user",
      "INSTEON_HUB_PASSWORD": "example-password",
      "INSTEON_HUB_HOST": "192.168.1.20"
    ])

  }

  @Test func removesMatchingQuotes() throws {

    let variables = try DotEnv.parse("""
      DOUBLE="two words"
      SINGLE='it is'
      EMPTY=""
      """)

    #expect(variables == ["DOUBLE": "two words", "SINGLE": "it is", "EMPTY": ""])

  }

  // Nothing in a value is interpreted, so a password can hold any character.
  @Test func keepsEverythingElseInAValue() throws {

    let variables = try DotEnv.parse(#"PASSWORD=a#b$HOME\n=c"#)

    #expect(variables == ["PASSWORD": #"a#b$HOME\n=c"#])

  }

  @Test func readsWindowsLineEndings() throws {

    let variables = try DotEnv.parse("FIRST=1\r\nSECOND=2\r\n")

    #expect(variables == ["FIRST": "1", "SECOND": "2"])

  }

  @Test func takesTheLastValueOfARepeatedKey() throws {

    #expect(try DotEnv.parse("KEY=first\nKEY=second") == ["KEY": "second"])

  }

  @Test func reportsAMalformedLineByNumberOnly() {

    #expect(throws: DotEnvError.malformedLine(2)) {

      try DotEnv.parse("GOOD=1\nnot a variable\n")

    }

    #expect(throws: DotEnvError.malformedLine(1)) {

      try DotEnv.parse("1KEY=value")

    }

    #expect(throws: DotEnvError.malformedLine(1)) {

      try DotEnv.parse(#"KEY="unclosed"#)

    }

    #expect(!DotEnvError.malformedLine(2).description.contains("not a variable"))

  }

  @Test func letsTheEnvironmentWinOverTheFile() {

    let merged = DotEnv.merging(
      ["INSTEON_HUB_HOST": "192.168.1.20", "INSTEON_HUB_PORT": "25105"],
      into: ["INSTEON_HUB_HOST": "192.168.1.30", "PATH": "/usr/bin"]
    )

    #expect(merged == ["INSTEON_HUB_HOST": "192.168.1.30", "INSTEON_HUB_PORT": "25105", "PATH": "/usr/bin"])

  }

}
