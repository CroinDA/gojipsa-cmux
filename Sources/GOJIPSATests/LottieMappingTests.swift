import Foundation
import GOJIPSACore

func runLottieMappingTests() async {
    await runSuite("Lottie — Emotion.lottieName mapping (every emotion has a lottie)") {
        await assertEqual(Emotion.idle.lottieName, "note_taking", "idle → note_taking")
        await assertEqual(Emotion.talking.lottieName, "Checking", "talking → Checking")
        await assertEqual(Emotion.celebrating.lottieName, "dancing", "celebrating → dancing")
        await assertEqual(Emotion.nagging.lottieName, "nodding_sighingly", "nagging → nodding_sighingly")
        await assertEqual(Emotion.alarmed.lottieName, "frightening", "alarmed → frightening")
        await assertEqual(Emotion.sleeping.lottieName, "note_taking", "sleeping → note_taking (TEMP until sleep lottie ships)")
    }

    await runSuite("Lottie — bundle resources present") {
        // SPM build copies Resources/lottie/ → Bundle.module.bundleURL/lottie/
        let bundle = gojipsaCoreResourceBundle
        let names = ["dancing", "note_taking", "nodding_sighingly", "Checking", "frightening"]
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
