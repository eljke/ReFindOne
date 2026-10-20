import Foundation
import Vision

/// OCR never uploads images. The expensive Vision request runs off the main actor.
struct OCRService {
    func extract(from data: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if #available(iOS 16, *) { request.automaticallyDetectsLanguage = true }
            let handler = VNImageRequestHandler(data: data, options: [:])
            try handler.perform([request])
            return (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value
    }
}
