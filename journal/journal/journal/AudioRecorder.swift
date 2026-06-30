import Foundation
import AVFoundation
import Observation

/// Records microphone audio to an .m4a file. macOS doesn't use AVAudioSession,
/// so AVAudioRecorder is driven directly.
@Observable
@MainActor
final class AudioRecorder: NSObject {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var outputURL: URL?

    func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .audio) { cont.resume(returning: $0) }
            }
        default:
            return false
        }
    }

    /// Begins recording to a temporary file. Returns false if it couldn't start.
    func start() -> Bool {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("journal-recording-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            guard rec.record() else { return false }
            recorder = rec
            outputURL = url
            isRecording = true
            elapsed = 0
            let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let rec = self.recorder else { return }
                    self.elapsed = rec.currentTime
                }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
            return true
        } catch {
            print("Audio recording failed to start: \(error)")
            return false
        }
    }

    /// Stops recording and returns the finished file URL.
    func stop() -> URL? {
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        let url = outputURL
        recorder = nil
        outputURL = nil
        return url
    }
}
