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

        let titleText = document.title.map(normalizeTextBlock)
        let paragraphTexts = document.paragraphs
            .map(normalizeTextBlock)
            .filter { !$0.isEmpty }

        let textBlocks = mergeTitle(titleText, with: paragraphTexts)
        return textBlocks.joined(separator: "\n\n")
    }

    private func mergeTitle(_ title: String?, with paragraphs: [String]) -> [String] {
        guard let title, !title.isEmpty else {
            return paragraphs
        }

        guard paragraphs.first != title else {
            return paragraphs
        }

        return [title] + paragraphs
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
    var isCJK: Bool {
        (0x4E00...0x9FFF).contains(value) ||
        (0x3400...0x4DBF).contains(value) ||
        (0xF900...0xFAFF).contains(value) ||
        (0x3040...0x30FF).contains(value) ||
        (0xAC00...0xD7AF).contains(value)
    }
}
