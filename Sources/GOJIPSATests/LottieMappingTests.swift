import Foundation
import GOJIPSACore

func runLottieMappingTests() async {
    await runSuite("Lottie — Emotion.lottieName mapping (every emotion has a lottie)") {
        await assertEqual(Emotion.idle.lottieName, "note_taking", "idle → note_taking")
        await assertEqual(Emotion.talking.lottieName, "Checking", "talking → Checking")
        await assertEqual(Emotion.celebrating.lottieName, "happy", "celebrating → happy")
        await assertEqual(Emotion.nagging.lottieName, "nagging", "nagging → nagging")
        await assertEqual(Emotion.alarmed.lottieName, "frightening", "alarmed → frightening")
        await assertEqual(Emotion.sleeping.lottieName, "sleepy", "sleeping → sleepy")
    }

    await runSuite("Lottie — all 11 bundle resources present") {
        // SPM build copies Resources/lottie/ → Bundle.module.bundleURL/lottie/
        let bundle = gojipsaCoreResourceBundle
        // All lottie files Gemini can freely choose from
        let names = [
            "note_taking", "Checking", "happy", "nagging", "frightening", "sleepy",
            "angry", "crying", "walking", "dancing", "nodding_sighingly"
        ]
        for name in names {
            let url = bundle.url(forResource: name, withExtension: "lottie", subdirectory: "lottie")
                ?? bundle.url(forResource: name, withExtension: "lottie")
                ?? bundle.resourceURL?.appendingPathComponent("lottie/\(name).lottie")
            await assertNotNil(url, "\(name).lottie should be locatable in GOJIPSACore bundle")
            if let u = url {
                let exists = FileManager.default.fileExists(atPath: u.path)
                await assert(exists, "\(name).lottie file must exist on disk at \(u.path)")
                let attrs = try? FileManager.default.attributesOfItem(atPath: u.path)
                let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
                await assert(size > 1000, "\(name).lottie should be a real file (> 1KB), got \(size)")
            }
        }
    }

    await runSuite("Lottie — resolver supports SwiftPM and Xcode resource layouts") {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("gojipsa-lottie-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }

        do {
            let spmRoot = root.appendingPathComponent("spm", isDirectory: true)
            let spmLottieDir = spmRoot.appendingPathComponent("lottie", isDirectory: true)
            try fm.createDirectory(at: spmLottieDir, withIntermediateDirectories: true)
            let spmURL = spmLottieDir.appendingPathComponent("note_taking.lottie")
            try Data("stub".utf8).write(to: spmURL)

            let xcodeRoot = root.appendingPathComponent("xcode", isDirectory: true)
            let xcodeLottieDir = xcodeRoot
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("lottie", isDirectory: true)
            try fm.createDirectory(at: xcodeLottieDir, withIntermediateDirectories: true)
            let xcodeURL = xcodeLottieDir.appendingPathComponent("note_taking.lottie")
            try Data("stub".utf8).write(to: xcodeURL)

            await assertEqual(
                LottieResourceResolver.url(named: "note_taking", under: spmRoot),
                spmURL,
                "resolver should find SwiftPM lottie/name.lottie layout"
            )
            await assertEqual(
                LottieResourceResolver.url(named: "note_taking", under: xcodeRoot),
                xcodeURL,
                "resolver should find Xcode Resources/lottie/name.lottie layout"
            )
            await assertNil(
                LottieResourceResolver.url(named: "../note_taking", under: xcodeRoot),
                "resolver should reject unsafe resource names"
            )
        } catch {
            await assert(false, "failed to create temp lottie resolver fixture: \(error)")
        }
    }

    await runSuite("Lottie — Comment.lottie overrides emotion.lottieName") {
        let c1 = Comment(text: "test", emotion: .talking, shouldReact: true, lottie: "angry")
        await assertEqual(c1.lottie, "angry", "explicit lottie override should be preserved")
        let c2 = Comment(text: "test", emotion: .talking, shouldReact: true)
        await assertEqual(c2.lottie, nil, "no override → lottie should be nil (use emotion.lottieName)")
    }

    await runSuite("Lottie — file format sanity (ZIP container)") {
        let bundle = gojipsaCoreResourceBundle
        guard let url = bundle.url(forResource: "dancing", withExtension: "lottie", subdirectory: "lottie")
                ?? bundle.url(forResource: "dancing", withExtension: "lottie")
                ?? bundle.resourceURL?.appendingPathComponent("lottie/dancing.lottie") else {
            await assert(false, "could not locate dancing.lottie"); return
        }
        // First 4 bytes of a ZIP file are PK\3\4
        let data = try? Data(contentsOf: url)
        guard let firstFour = data?.prefix(4) else {
            await assert(false, "could not read dancing.lottie"); return
        }
        let pkSignature: [UInt8] = [0x50, 0x4B, 0x03, 0x04]
        await assertEqual(Array(firstFour), pkSignature,
                          "dotLottie format = ZIP container — first 4 bytes must be PK\\3\\4")
    }
}
