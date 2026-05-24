//
//  DocRecognizer.swift
//  OcrServer
//
//  Created by Riddle Ling on 2026/5/24.
//

import Foundation
import Vision

@available(iOS 26.0, *)
class DocRecognizer {
    let usesLanguageCorrection : Bool
    let automaticallyDetectsLanguage : Bool
    
    init(usesLanguageCorrection: Bool = true, automaticallyDetectsLanguage: Bool = true) {
        self.usesLanguageCorrection = usesLanguageCorrection
        self.automaticallyDetectsLanguage = automaticallyDetectsLanguage
    }
    
    func recognizeParagraphText(from imageData: Data) async -> String {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.automaticallyDetectLanguage = automaticallyDetectsLanguage
        request.textRecognitionOptions.useLanguageCorrection = usesLanguageCorrection
        request.textRecognitionOptions.maximumCandidateCount = 1

        let observations = try? await request.perform(on: imageData)

        guard let document = observations?.first?.document else {
            return ""
        }

        let paragraphTexts = document.paragraphs
            .map(normalizeTextBlock)
            .filter { !$0.isEmpty }

        return mergeParagraphsSplitByOCR(paragraphTexts).joined(separator: "\n\n")
    }

    private func normalizeTextBlock(_ textBlock: DocumentObservation.Container.Text) -> String {
        let lines = textBlock.lines
            .map(\.transcript)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.isEmpty {
            return normalizeTranscript(textBlock.transcript)
        }

        return joinLinesInSameParagraph(lines)
    }

    private func mergeParagraphsSplitByOCR(_ paragraphs: [String]) -> [String] {
        paragraphs.reduce(into: []) { result, paragraph in
            guard let previousParagraph = result.last,
                  shouldMergeParagraph(previousParagraph, with: paragraph) else {
                result.append(paragraph)
                return
            }

            result[result.count - 1] = previousParagraph
                + (shouldInsertSpace(between: previousParagraph, and: paragraph) ? " " : "")
                + paragraph
        }
    }

    private func shouldMergeParagraph(_ previousParagraph: String, with nextParagraph: String) -> Bool {
        guard let previousLastScalar = previousParagraph.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.last,
              let nextFirstScalar = nextParagraph.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.first else {
            return false
        }

        guard !previousLastScalar.isStrongParagraphEnding else {
            return false
        }

        return nextFirstScalar.isLowercaseLatin
    }

    private func normalizeTranscript(_ text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return joinLinesInSameParagraph(lines)
    }

    private func joinLinesInSameParagraph(_ lines: [String]) -> String {
        lines.reduce(into: "") { result, line in
            guard !result.isEmpty else {
                result = line
                return
            }

            result += shouldInsertSpace(between: result, and: line) ? " \(line)" : line
        }
    }

    private func shouldInsertSpace(between previousText: String, and nextText: String) -> Bool {
        guard let previousScalar = previousText.unicodeScalars.last,
              let nextScalar = nextText.unicodeScalars.first else {
            return false
        }

        return !previousScalar.isCJK && !nextScalar.isCJK
    }
}

private extension Unicode.Scalar {
    var isLowercaseLatin: Bool {
        (0x0061...0x007A).contains(value)
    }

    var isStrongParagraphEnding: Bool {
        ".!?。！？:：;；".unicodeScalars.contains(self)
    }

    var isCJK: Bool {
        (0x4E00...0x9FFF).contains(value) ||
        (0x3400...0x4DBF).contains(value) ||
        (0xF900...0xFAFF).contains(value) ||
        (0x3040...0x30FF).contains(value) ||
        (0xAC00...0xD7AF).contains(value)
    }
}
