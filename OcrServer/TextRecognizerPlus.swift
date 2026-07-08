//
//  TextRecognizerPlus.swift
//  OcrServer
//
//  Extensie peste TextRecognizer:
//   1. OCR la nivel de CUVANT (nu linie) — necesar pentru XY-cut
//   2. Detectie automata a orientarii (0/90/180/270) + rotire fizica a imaginii
//   3. Crop per bon + normalizare contrast (pentru print termic slab) + re-OCR pe crop
//
//  Pipeline recomandat in ruta /upload:
//    data -> normalizedCGImage() -> wordBoxes() -> ReceiptSegmenter.segment()
//         -> pentru fiecare segment: cropAndReOCR() -> processOcrResult(...)
//

import Foundation
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO

final class TextRecognizerPlus {

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - 1. Orientare: gaseste rotatia corecta si intoarce imaginea "in picioare"

    /// Ruleaza un OCR rapid (.fast) in cele 4 orientari si alege scorul maxim.
    /// Intoarce CGImage-ul deja rotit fizic, ca tot restul pipeline-ului
    /// sa lucreze in coordonate normale (.up).
    func normalizedCGImage(from data: Data) async -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }

        var bestScore = -1.0
        var bestOrientation: CGImagePropertyOrientation = .up

        print("[ROTATION] Probing orientations...")
        for orientation in [CGImagePropertyOrientation.up, .right, .down, .left] {
            let rotated = rotate(cg, orientation: orientation)
            var probe = RecognizeTextRequest()
            probe.recognitionLevel = .fast          // doar pentru scoring, e ieftin
            probe.usesLanguageCorrection = false
            let obs = (try? await probe.perform(on: rotated)) ?? []

            let W = Double(rotated.width)
            let H = Double(rotated.height)
            var score = 0.0
            var horizCount = 0
            for o in obs {
                if let c = o.topCandidates(1).first {
                    let rect = o.boundingBox
                    let pixelW = rect.width * W
                    let pixelH = rect.height * H
                    if pixelW > pixelH * 1.2 {
                        score += Double(c.string.count) * Double(c.confidence)
                        horizCount += 1
                    }
                }
            }
            let name: String
            switch orientation {
            case .up: name = "up"
            case .right: name = "right"
            case .down: name = "down"
            case .left: name = "left"
            default: name = "unknown"
            }
            print("  Orientation \(name): score=\(score), horizontalLines=\(horizCount), totalLines=\(obs.count)")
            
            if score > bestScore {
                bestScore = score
                bestOrientation = orientation
            }
        }
        let bestName: String
        switch bestOrientation {
        case .up: bestName = "up"
        case .right: bestName = "right"
        case .down: bestName = "down"
        case .left: bestName = "left"
        default: bestName = "unknown"
        }
        print("[ROTATION] Best orientation selected: \(bestName)")
        return rotate(cg, orientation: bestOrientation)
    }

    private func rotate(_ image: CGImage, orientation: CGImagePropertyOrientation) -> CGImage {
        guard orientation != .up else { return image }
        let ci = CIImage(cgImage: image).oriented(orientation)
        return ciContext.createCGImage(ci, from: ci.extent) ?? image
    }

    // MARK: - 2. OCR la nivel de cuvant

    /// Ruleaza Vision o singura data (observatii = linii), apoi sparge fiecare
    /// candidat in cuvinte si cere boundingBox(for:) pe range-ul fiecarui cuvant.
    /// Asa obtii box-uri de cuvant fara sa pierzi acuratetea lui .accurate.
    func wordBoxes(on image: CGImage) async -> (boxes: [OCRBoxItem], width: Int, height: Int) {
        let W = image.width
        let H = image.height

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false   // IMPORTANT: pe bonuri, corectia "repara"
                                                 // gresit coduri/CUI-uri; o vrem OFF aici
        request.recognitionLanguages = [Locale.Language(identifier: "ro-RO"),
                                        Locale.Language(identifier: "en-US")]

        let observations = (try? await request.perform(on: image)) ?? []

        var items: [OCRBoxItem] = []
        items.reserveCapacity(observations.count * 6)

        for obs in observations {
            guard let best = obs.topCandidates(1).first else { continue }
            let str = best.string

            // spargem candidatul in cuvinte, pastrand range-urile in stringul original
            var searchStart = str.startIndex
            while searchStart < str.endIndex {
                // sarim peste spatii
                while searchStart < str.endIndex, str[searchStart].isWhitespace {
                    searchStart = str.index(after: searchStart)
                }
                guard searchStart < str.endIndex else { break }
                var end = searchStart
                while end < str.endIndex, !str[end].isWhitespace {
                    end = str.index(after: end)
                }
                let range = searchStart..<end
                let word = String(str[range])
                searchStart = end

                // box-ul cuvantului, in coordonate normalizate Vision (origine jos-stanga)
                guard let quad = try? best.boundingBox(for: range) else {
                    continue
                }
                let corners = [quad.topLeft, quad.topRight, quad.bottomLeft, quad.bottomRight]
                let xs = corners.map { Double($0.x) * Double(W) }
                let ys = corners.map { (1.0 - Double($0.y)) * Double(H) }   // flip Y -> origine sus-stanga

                let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
                let minY = ys.min() ?? 0, maxY = ys.max() ?? 0

                items.append(OCRBoxItem(text: word,
                                        x: minX, y: minY,
                                        w: maxX - minX, h: maxY - minY,
                                        rect: nil))
            }
        }
        return (items, W, H)
    }

    // MARK: - 3. Crop per bon + enhance + re-OCR

    /// Dupa ce ReceiptSegmenter a impartit box-urile in clustere, ia dreptunghiul
    /// fiecarui cluster, decupeaza-l din imaginea mare, normalizeaza contrastul
    /// si re-ruleaza OCR DOAR pe crop. Pe crop, Vision vede un singur bon,
    /// deci liniile nu se mai amesteca intre bonuri si calitatea creste vizibil
    /// (mai ales la print termic slab, cazul ROG GAZ).
    func cropAndReOCR(image: CGImage,
                      clusterBoxes: [OCRBoxItem],
                      marginRatio: Double = 0.03) async -> [OCRBoxItem] {
        guard !clusterBoxes.isEmpty else { return [] }

        let minX = clusterBoxes.map { $0.x }.min()!
        let minY = clusterBoxes.map { $0.y }.min()!
        let maxX = clusterBoxes.map { $0.x + $0.w }.max()!
        let maxY = clusterBoxes.map { $0.y + $0.h }.max()!

        let mX = (maxX - minX) * marginRatio
        let mY = (maxY - minY) * marginRatio

        let cropRect = CGRect(x: max(0, minX - mX),
                              y: max(0, minY - mY),
                              width: min(Double(image.width),  maxX + mX) - max(0, minX - mX),
                              height: min(Double(image.height), maxY + mY) - max(0, minY - mY))

        guard let crop = image.cropping(to: cropRect) else { return clusterBoxes }

        let enhanced = enhanceForThermalPrint(crop)

        var (words, _, _) = await wordBoxes(on: enhanced)

        // mutam coordonatele crop-ului inapoi in spatiul imaginii mari,
        // ca restul pipeline-ului (si debug-ul) sa ramana consistent
        for i in words.indices {
            words[i] = OCRBoxItem(text: words[i].text,
                                  x: words[i].x + cropRect.origin.x,
                                  y: words[i].y + cropRect.origin.y,
                                  w: words[i].w, h: words[i].h,
                                  rect: nil)
        }
        // fallback: daca re-OCR-ul a iesit mai prost decat prima trecere, pastreaz-o pe prima
        return words.count >= clusterBoxes.count / 2 ? words : clusterBoxes
    }

    /// Normalizare pentru bonuri termice decolorate:
    /// grayscale -> contrast crescut -> sharpen usor.
    /// (CIDocumentEnhancer e alternativa "totul inclus" pe iOS 17+,
    ///  dar combinatia manuala de mai jos e mai predictibila pe bonuri.)
    private func enhanceForThermalPrint(_ image: CGImage) -> CGImage {
        var ci = CIImage(cgImage: image)

        // 1) grayscale
        let mono = CIFilter.colorControls()
        mono.inputImage = ci
        mono.saturation = 0
        mono.contrast = 1.35        // > 1.0 intensifica textul sters
        mono.brightness = 0.02
        ci = mono.outputImage ?? ci

        // 2) sharpen usor — ajuta Vision la fonturile de imprimanta termica
        let sharp = CIFilter.sharpenLuminance()
        sharp.inputImage = ci
        sharp.sharpness = 0.4
        ci = sharp.outputImage ?? ci

        // 3) upscale 2x daca bonul e mic in cadru (< ~900 px latime);
        //    Vision citeste vizibil mai bine sub 1000px dupa upscale
        if image.width < 900 {
            ci = ci.transformed(by: CGAffineTransform(scaleX: 2, y: 2))
        }

        return ciContext.createCGImage(ci, from: ci.extent) ?? image
    }
}
