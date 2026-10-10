import AppKit
import RecorgiCore
import RecorgiCapture

/// Dev-only harness, gated behind the RECORGI_STRESS_TEST env var — runs a
/// matrix of record/stop cycles with different audio-track and region
/// combinations automatically, so the -11800/-16122 investigation doesn't
/// need a human clicking Record for every single variable. Not wired into
/// any UI; only reachable by launching the built binary with that env var
/// set. Safe to delete once the investigation is closed.
@MainActor
enum StressTestRunner {
    private struct Config {
        let label: String
        let systemAudio: Bool
        let mic: Bool
        let region: (DisplayInfo) -> CaptureRegion
    }

    static func run(engine: ScreenRecordingEngine, settings: RecordingSettings) async {
        guard let display = try? await CaptureSourceProvider().availableDisplays().first else {
            print("STRESS: no display found, aborting")
            NSApplication.shared.terminate(nil)
            return
        }
        print("STRESS: using display \(display.name) \(display.width)x\(display.height)")

        let smallArea: (DisplayInfo) -> CaptureRegion = { d in
            .area(d, CGRect(x: 0, y: 0, width: 800, height: 600))
        }

        var configs: [Config] = [
            Config(label: "video-only-fullscreen", systemAudio: false, mic: false, region: { _ in .primaryDisplay }),
            Config(label: "video+sysaudio-fullscreen", systemAudio: true, mic: false, region: { _ in .primaryDisplay }),
            Config(label: "video+mic-fullscreen", systemAudio: false, mic: true, region: { _ in .primaryDisplay }),
            Config(label: "video+both-fullscreen", systemAudio: true, mic: true, region: { _ in .primaryDisplay }),
            Config(label: "video-only-smallarea", systemAudio: false, mic: false, region: smallArea),
            Config(label: "video+both-smallarea", systemAudio: true, mic: true, region: smallArea),
        ]
        // RECORGI_STRESS_ONLY=<substring> narrows the matrix to configs
        // whose label contains it, for isolating one case quickly.
        if let only = ProcessInfo.processInfo.environment["RECORGI_STRESS_ONLY"] {
            configs = configs.filter { $0.label.contains(only) }
        }

        let iterations = 3
        let recordSeconds: UInt64 = 4
        let gapSeconds: UInt64 = 1

        for config in configs {
            for i in 1...iterations {
                settings.isSystemAudioEnabled = config.systemAudio
                settings.isMicrophoneEnabled = config.mic
                settings.captureRegion = config.region(display)

                print("STRESS [\(config.label) #\(i)]: starting")
                do {
                    try await engine.start(settings: settings)
                } catch {
                    print("STRESS [\(config.label) #\(i)]: start() threw \(error)")
                    try? await Task.sleep(nanoseconds: gapSeconds * 1_000_000_000)
                    continue
                }
                try? await Task.sleep(nanoseconds: recordSeconds * 1_000_000_000)
                await engine.stop()
                print("STRESS [\(config.label) #\(i)]: stopped, lastError=\(engine.lastError ?? "nil")")
                try? await Task.sleep(nanoseconds: gapSeconds * 1_000_000_000)
            }
        }

        print("STRESS: all configs complete")
        NSApplication.shared.terminate(nil)
    }
}
