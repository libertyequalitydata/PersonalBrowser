@preconcurrency import AVFoundation
import Foundation
import Speech

@MainActor
final class BrowserTranscriptionController: ObservableObject {
    @Published private(set) var activeArtifactID: UUID?

    func transcribe(artifact: LibraryArtifact, url: URL, store: BrowserStore) {
        guard activeArtifactID == nil else {
            store.showNotice("A transcription is already running", systemImage: "waveform.badge.exclamationmark")
            return
        }
        guard artifact.kind == .audio || artifact.kind == .video else { return }

        activeArtifactID = artifact.id
        store.showNotice("Preparing transcription", systemImage: "waveform")

        Task {
            do {
                let result = try await Self.transcribe(url: url, kind: artifact.kind)
                store.setLibraryTranscript(
                    result.text,
                    localeIdentifier: result.localeIdentifier,
                    artifactID: artifact.id
                )
                store.showNotice("Transcript added to Library", systemImage: "text.badge.checkmark")
            } catch {
                store.showNotice(
                    error.localizedDescription,
                    systemImage: "exclamationmark.triangle.fill",
                    isFailure: true
                )
            }
            activeArtifactID = nil
        }
    }

    private static func transcribe(
        url: URL,
        kind: LibraryArtifactKind
    ) async throws -> (text: String, localeIdentifier: String) {
        let authorization = await requestAuthorization()
        guard authorization == .authorized else { throw TranscriptionError.permissionDenied }

        let locale = Locale.current
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.onDeviceUnavailable
        }

        let preparedURL: URL
        var temporaryURL: URL?
        if kind == .video {
            let extracted = try await extractAudio(from: url)
            preparedURL = extracted
            temporaryURL = extracted
        } else {
            preparedURL = url
        }
        defer {
            if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
        }

        let request = SFSpeechURLRecognitionRequest(url: preparedURL)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true

        let text = try await recognize(request: request, recognizer: recognizer)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranscriptionError.noSpeech
        }
        return (text, locale.identifier)
    }

    private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func recognize(
        request: SFSpeechURLRecognitionRequest,
        recognizer: SFSpeechRecognizer
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            var task: SFSpeechRecognitionTask?
            task = recognizer.recognitionTask(with: request) { result, error in
                guard !resumed else { return }
                if let error {
                    resumed = true
                    task?.cancel()
                    continuation.resume(throwing: error)
                } else if let result, result.isFinal {
                    resumed = true
                    task?.finish()
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    private static func extractAudio(from url: URL) async throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("browser-transcription-\(UUID().uuidString).m4a")
        let asset = AVURLAsset(url: url)
        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw TranscriptionError.audioExtractionFailed
        }
        exporter.outputURL = destination
        exporter.outputFileType = .m4a

        let exporterBox = ExportSessionBox(exporter)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exporter.exportAsynchronously {
                let exporter = exporterBox.value
                switch exporter.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: exporter.error ?? TranscriptionError.audioExtractionFailed)
                default:
                    continuation.resume(throwing: TranscriptionError.audioExtractionFailed)
                }
            }
        }
        return destination
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let value: AVAssetExportSession

    init(_ value: AVAssetExportSession) {
        self.value = value
    }
}

enum TranscriptionError: LocalizedError {
    case permissionDenied
    case recognizerUnavailable
    case onDeviceUnavailable
    case audioExtractionFailed
    case noSpeech

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Speech recognition permission was not granted."
        case .recognizerUnavailable: "Speech recognition is currently unavailable."
        case .onDeviceUnavailable: "On-device transcription is not available for the current language."
        case .audioExtractionFailed: "The video audio could not be prepared for transcription."
        case .noSpeech: "No transcribable speech was found."
        }
    }
}
