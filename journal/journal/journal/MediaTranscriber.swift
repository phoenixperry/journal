import Foundation
import Speech

/// On-device transcription of an audio or video file's speech to text.
enum MediaTranscriber {
    enum TranscribeError: LocalizedError {
        case notAuthorized
        case unavailable
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized: "Speech recognition permission was not granted."
            case .unavailable: "Speech recognition isn't available for your language."
            case .failed(let m): "Couldn't transcribe: \(m)"
            }
        }
    }

    static func requestAuthorization() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
    }

    /// Transcribes the speech in an audio or video file. Prefers on-device
    /// recognition (private, offline) when the language model supports it.
    static func transcribe(url: URL) async throws -> String {
        guard await requestAuthorization() else { throw TranscribeError.notAuthorized }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw TranscribeError.unavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.shouldReportPartialResults = false

        final class ResumeOnce { var done = false }
        let guardBox = ResumeOnce()

        return try await withCheckedThrowingContinuation { cont in
            recognizer.recognitionTask(with: request) { result, error in
                guard !guardBox.done else { return }
                if let error {
                    guardBox.done = true
                    cont.resume(throwing: TranscribeError.failed(error.localizedDescription))
                } else if let result, result.isFinal {
                    guardBox.done = true
                    cont.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
}
