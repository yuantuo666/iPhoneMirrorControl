import CoreGraphics
import Foundation
import Vision

public struct OCRHit {
    public let text: String
    public let confidence: Double
    /// Bounding box in normalized display coordinates, top-left origin.
    public let x: Double
    public let y: Double
    public let w: Double
    public let h: Double
    public var centerX: Double { x + w / 2 }
    public var centerY: Double { y + h / 2 }
}

public enum OCR {
    public static func recognize(cgImage: CGImage, languages: [String] = ["zh-Hans", "en-US"],
                                 level: VNRequestTextRecognitionLevel = .accurate) throws -> [OCRHit] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        if #available(macOS 13.0, *) {
            request.revision = VNRecognizeTextRequestRevision3
        }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        var hits: [OCRHit] = []
        for obs in request.results ?? [] {
            guard let cand = obs.topCandidates(1).first else { continue }
            let bb = obs.boundingBox // normalized, bottom-left origin
            hits.append(OCRHit(text: cand.string,
                               confidence: Double(cand.confidence),
                               x: Double(bb.minX),
                               y: Double(1 - bb.maxY),
                               w: Double(bb.width),
                               h: Double(bb.height)))
        }
        return hits
    }
}
