import Foundation
import GOJIPSACore

func runSecretRedactorTests() async {
    await runSuite("SecretRedactor — secrets are redacted") {
        let secrets: [(String, String, String)] = [
            ("openai_key=sk-proj-abc1234567890DEF1234567890ghij1234", "sk-proj-abc1234567890DEF1234567890ghij1234", "OpenAI key"),
            ("api_key: AIzaSyTESTfakekey1234567890ABCDEfghIJKLmno",     "AIzaSyTESTfakekey1234567890ABCDEfghIJKLmno",     "Google API key"),
            ("GH_TOKEN=gho_AAAABBBBCCCCDDDDEEEEFFFFGGGGHHHH11",      "gho_AAAABBBBCCCCDDDDEEEEFFFFGGGGHHHH11",      "GitHub token"),
            ("AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE",                "AKIAIOSFODNN7EXAMPLE",                          "AWS access key"),
            ("Authorization: Bearer abc.def.ghi.jklmnopqrstuv0123",  "Bearer abc.def.ghi.jklmnopqrstuv0123",         "Bearer token"),
        ]
        for (input, sensitive, label) in secrets {
            let out = SecretRedactor.redact(input)
            await assert(!out.contains(sensitive), "\(label) should be redacted (input: \(input))")
        }
    }

    await runSuite("SecretRedactor — JWT and PEM markers") {
        let jwtIn = "session=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkw.SflKxwRJSMeKKF30"
        let jwtOut = SecretRedactor.redact(jwtIn)
        await assert(jwtOut.contains("***JWT-REDACTED***"), "JWT marker should appear in: \(jwtOut)")

        let pemIn = """
        -----BEGIN RSA PRIVATE KEY-----
        MIIEowIBAAKCAQEAm0fakekeydataforTESTINGonly
        xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
        -----END RSA PRIVATE KEY-----
        """
        let pemOut = SecretRedactor.redact(pemIn)
        await assert(!pemOut.contains("MIIEowIBAAKCAQEAm0fakekeydata"), "PEM body should be redacted")
        await assert(pemOut.contains("***PRIVATE-KEY-REDACTED***"), "PEM marker should appear")
    }

    await runSuite("SecretRedactor — password assignment") {
        let out1 = SecretRedactor.redact("password=hunter2supersecret")
        await assert(!out1.contains("hunter2supersecret"), "password value should be redacted")

        let out2 = SecretRedactor.redact("secret: \"abc123XYZ789veryLongValue\"")
        await assert(!out2.contains("abc123XYZ789veryLongValue"), "quoted secret should be redacted")
    }

    await runSuite("SecretRedactor — preserves benign text") {
        let benign = "hello world, building swift app"
        let out = SecretRedactor.redact(benign)
        await assertEqual(out, benign, "benign text should be unchanged")

        let shortPwd = "passwd=abc"  // < 8 chars
        let outShort = SecretRedactor.redact(shortPwd)
        await assertEqual(outShort, shortPwd, "short value should not match (< 8 chars)")
    }

    await runSuite("SecretRedactor — idempotent") {
        let input = "AIzaSyTESTfakekey1234567890ABCDEfghIJKLmno bearer Bearer abcdefghijklmnopqrst"
        let once = SecretRedactor.redact(input)
        let twice = SecretRedactor.redact(once)
        await assertEqual(once, twice, "running redact twice should be no-op")
    }
}
