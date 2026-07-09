//
//  ReceiptPipelinePatch.swift
//  Componente de integrat în VaporServer.swift — fixuri pentru testul multi-bon.
//
//  ORDINEA CORECTĂ A PIPELINE-ULUI:
//    1. OCR pe toată imaginea la nivel de CUVÂNT (nu de linie!)
//    2. Segmentare: XY-cut recursiv pe box-uri + split semantic pe ancore de antet
//    3. Extracție per bon (CUI hardened, total cu blacklist, validare matematică)
//    4. Un singur batch ANAF v9 pentru toate CUI-urile + fuzzy match pe denumire
//
//  NOTĂ Vision: RecognizeTextRequest întoarce observații pe LINII. Pentru cuvinte,
//  folosește `observation.topCandidates(1).first?.boundingBox(for:)` pe range-urile
//  fiecărui cuvânt din string, sau iterează pe subranges. Un box de linie care
//  traversează 2 bonuri distruge tot ce urmează — de aceea nivelul CUVÂNT e obligatoriu.
//  Pentru bonuri rotite: rulează request-ul cu orientation .up/.right/.down/.left
//  și păstrează varianta cu cele mai multe caractere recunoscute.

import Foundation

// MARK: - 1. Segmentare XY-cut recursiv (înlocuiește segmentReceipts / recursiveSplit)

enum ReceiptSegmenter {

    /// Împarte recursiv setul de cuvinte la cel mai mare gol care traversează complet regiunea.
    /// Golurile interne ale unui bon (coloana etichete/sume) sunt întrerupte de rândurile late
    /// (antet, adresă), deci nu declanșează split. Golurile DINTRE bonuri sunt continue.
    static func segment(_ words: [OCRBoxItem]) -> [[OCRBoxItem]] {
        print("[SEGMENTER] === START === words count: \(words.count)")
        let heights = words.map { $0.h }.sorted()
        let mh = heights.isEmpty ? 15.0 : heights[heights.count / 2]
        print("[SEGMENTER] Median height (mh): \(mh)")

        var parts: [[OCRBoxItem]] = []
        xycut(words, minGapX: mh * 1.0, minGapY: mh * 1.5, into: &parts)
        print("[SEGMENTER] Parts after xycut: \(parts.count)")
        for (i, p) in parts.enumerated() {
            let box = bbox(p)
            print("  Part \(i): \(p.count) words, bbox: x=\(box.minX..<(box.maxX)) y=\(box.minY..<(box.maxY))")
        }

        let filteredParts = parts.filter { $0.count >= 8 }
        print("[SEGMENTER] Parts after filtering count>=8: \(filteredParts.count)")

        var merged = mergeFragments(filteredParts, medianHeight: mh)
        print("[SEGMENTER] Parts after mergeFragments: \(merged.count)")
        for (i, m) in merged.enumerated() {
            print("  Merged \(i): \(m.count) words")
        }

        let split = merged.flatMap { splitByHeaderAnchors($0) }
        print("[SEGMENTER] Parts after splitByHeaderAnchors: \(split.count)")

        let finalSegments = split.filter { $0.count >= 14 }
        print("[SEGMENTER] Final segments count>=14: \(finalSegments.count)")

        // FALLBACK: dacă xycut a produs doar 1 segment dar sunt >=50 cuvinte,
        // imaginea e probabil rotită sau bonurile se ating. Folosim anchor-based clustering.
        if finalSegments.count <= 1 && words.count >= 50 {
            let anchored = anchorBasedSegment(words)
            if anchored.count > finalSegments.count {
                print("[SEGMENTER] Anchor-based fallback produced \(anchored.count) segments (xycut had \(finalSegments.count))")
                return anchored
            }
        }
        
        return finalSegments.sorted { bbox($0).minX < bbox($1).minX || (abs(bbox($0).minX - bbox($1).minX) < 500 && bbox($0).minY < bbox($1).minY) }
    }

    // MARK: - Anchor-based segmentation (fallback for rotated/touching receipts)

    /// Găsește boxurile cu CUI/COD FISCAL (exclud CLIENT/CNP/CUMPARATOR)
    /// și grupează toate celelalte boxuri la cel mai apropiat anchor prin distanță Euclidiană.
    private static func anchorBasedSegment(_ words: [OCRBoxItem]) -> [[OCRBoxItem]] {
        let buyerPattern = try! NSRegularExpression(pattern: "CLIENT|CUMPARATOR|BENEF|CNP", options: .caseInsensitive)
        let cuiPattern = try! NSRegularExpression(pattern: "COD\\s*FISCAL|COD\\s*IDENTIFICARE|C\\.?\\s*I\\.?\\s*F[^A-Z]", options: .caseInsensitive)

        var anchors: [OCRBoxItem] = []
        
        // 1) Găsim boxuri cu COD FISCAL / CIF care conțin cel puțin 4 cifre
        for box in words {
            let text = box.text
            let range = NSRange(text.startIndex..., in: text)
            if buyerPattern.firstMatch(in: text, range: range) != nil { continue }
            if cuiPattern.firstMatch(in: text, range: range) != nil {
                let digitCount = text.filter { $0.isNumber }.count
                if digitCount >= 4 {
                    anchors.append(box)
                }
            }
        }
        
        // 2) Căutăm și "CIF" standalone urmat de un box cu cifre pe aceeași coloană
        for box in words {
            let t = box.text.uppercased().trimmingCharacters(in: .punctuationCharacters).trimmingCharacters(in: .whitespaces)
            let range = NSRange(box.text.startIndex..., in: box.text)
            if buyerPattern.firstMatch(in: box.text, range: range) != nil { continue }
            if t == "CIF" || t == "C I F" {
                for b2 in words {
                    if abs(b2.x - box.x) < 30 {
                        let digits = b2.text.replacingOccurrences(of: " ", with: "").filter { $0.isNumber }.count
                        if digits >= 7 {
                            if !anchors.contains(where: { abs($0.x - b2.x) < 20 && abs($0.y - b2.y) < 30 }) {
                                anchors.append(b2)
                            }
                            break
                        }
                    }
                }
            }
        }

        // 3) Deduplicare anchors prea apropiate
        var deduped: [OCRBoxItem] = []
        for a in anchors {
            if !deduped.contains(where: { abs($0.x - a.x) < 40 && abs($0.y - a.y) < 40 }) {
                deduped.append(a)
            }
        }
        anchors = deduped
        
        print("[SEGMENTER-ANCHOR] Found \(anchors.count) CUI anchors")
        for (i, a) in anchors.enumerated() {
            print("  Anchor \(i): '\(a.text)' at (\(Int(a.x + a.w/2)), \(Int(a.y + a.h/2)))")
        }
        
        guard anchors.count >= 2 else {
            print("[SEGMENTER-ANCHOR] Not enough anchors, returning all as 1 segment")
            return [words]
        }

        // 4) Asignare prin distanță Euclidiană la cel mai apropiat anchor
        let centers = anchors.map { (x: $0.x + $0.w / 2, y: $0.y + $0.h / 2) }
        var groups: [[OCRBoxItem]] = Array(repeating: [], count: anchors.count)
        
        for box in words {
            let bx = box.x + box.w / 2
            let by = box.y + box.h / 2
            var bestIdx = 0
            var bestDist = Double.greatestFiniteMagnitude
            for (i, c) in centers.enumerated() {
                let d = (bx - c.x) * (bx - c.x) + (by - c.y) * (by - c.y)
                if d < bestDist {
                    bestDist = d
                    bestIdx = i
                }
            }
            groups[bestIdx].append(box)
        }
        
        // 5) Filtrare grupuri prea mici (zgomot)
        let result = groups.filter { $0.count >= 5 }
        print("[SEGMENTER-ANCHOR] Final clusters: \(result.count)")
        for (i, g) in result.enumerated() {
            print("  Cluster \(i): \(g.count) boxes")
        }
        return result
    }

    private static func xycut(_ ws: [OCRBoxItem], minGapX: Double, minGapY: Double, into out: inout [[OCRBoxItem]]) {
        guard ws.count >= 10 else { out.append(ws); return }

        func bestGap(axis: Character) -> (size: Double, split: Double)? {
            let intervals = ws.map { axis == "x" ? ($0.x, $0.x + $0.w) : ($0.y, $0.y + $0.h) }
                              .sorted { $0.0 < $1.0 }
            var merged: [(Double, Double)] = [intervals[0]]
            for (a, b) in intervals.dropFirst() {
                if a <= merged[merged.count - 1].1 + 2 {
                    merged[merged.count - 1].1 = max(merged[merged.count - 1].1, b)
                } else { merged.append((a, b)) }
            }
            var best: (Double, Double)? = nil
            for i in 0..<(merged.count - 1) {
                let g = merged[i + 1].0 - merged[i].1
                if best == nil || g > best!.0 { best = (g, (merged[i].1 + merged[i + 1].0) / 2) }
            }
            return best
        }

        let gx = bestGap(axis: "x"), gy = bestGap(axis: "y")
        let sx = gx?.size ?? 0, sy = gy?.size ?? 0
        if sx < minGapX && sy < minGapY { out.append(ws); return }

        if sx / minGapX >= sy / minGapY, let split = gx?.split {
            xycut(ws.filter { $0.x + $0.w / 2 <  split }, minGapX: minGapX, minGapY: minGapY, into: &out)
            xycut(ws.filter { $0.x + $0.w / 2 >= split }, minGapX: minGapX, minGapY: minGapY, into: &out)
        } else if let split = gy?.split {
            xycut(ws.filter { $0.y + $0.h / 2 <  split }, minGapX: minGapX, minGapY: minGapY, into: &out)
            xycut(ws.filter { $0.y + $0.h / 2 >= split }, minGapX: minGapX, minGapY: minGapY, into: &out)
        } else { out.append(ws) }
    }

    private static func bbox(_ c: [OCRBoxItem]) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        (c.map { $0.x }.min() ?? 0, c.map { $0.y }.min() ?? 0,
         c.map { $0.x + $0.w }.max() ?? 0, c.map { $0.y + $0.h }.max() ?? 0)
    }

    private static let headerAnchor = try! NSRegularExpression(
        pattern: "NUMAR\\s+BON|COD\\s+FISCAL|COD\\s+IDENTIFICARE", options: [.caseInsensitive])

    private static func hasHeader(_ c: [OCRBoxItem]) -> Bool {
        let t = c.sorted { ($0.y, $0.x) < ($1.y, $1.x) }.map { $0.text }.joined(separator: " ").uppercased()
        return headerAnchor.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
    }

    /// Unește fragmentele antet/corp din aceeași coloană. Regulă: niciodată 2 antete în același cluster.
    private static func mergeFragments(_ parts: [[OCRBoxItem]], medianHeight mh: Double) -> [[OCRBoxItem]] {
        var merged = parts
        var changed = true
        while changed {
            changed = false
            outer: for i in 0..<merged.count {
                for j in (i + 1)..<merged.count {
                    let a = bbox(merged[i]), b = bbox(merged[j])
                    let inter = min(a.maxX, b.maxX) - max(a.minX, b.minX)
                    let xOverlap = inter > 0 ? inter / min(a.maxX - a.minX, b.maxX - b.minX) : 0
                    let vGap = max(b.minY - a.maxY, a.minY - b.maxY, 0)
                    let twoHeaders = hasHeader(merged[i]) && hasHeader(merged[j])
                    if xOverlap > 0.45 && vGap < mh * 7 && !(twoHeaders && vGap > mh * 3) {
                        merged[i].append(contentsOf: merged[j])
                        merged.remove(at: j)
                        changed = true
                        break outer
                    }
                }
            }
        }
        return merged
    }

    /// Un bon are exact un antet. Dacă un cluster conține >= 2 "NUMAR BON FISCAL", taie între ele.
    private static func splitByHeaderAnchors(_ c: [OCRBoxItem]) -> [[OCRBoxItem]] {
        let sorted = c.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        var anchorYs: [Double] = []
        for (idx, w) in sorted.enumerated() {
            let t = w.text.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
            if t == "NUMAR" || t == "WOMAR" || t == "NOMAR" {
                let next = sorted[(idx + 1)..<min(idx + 3, sorted.count)].map { $0.text.uppercased() }.joined(separator: " ")
                if next.contains("BON") { anchorYs.append(w.y) }
            }
        }
        guard anchorYs.count >= 2 else { return [c] }
        anchorYs.sort()
        let bounds = anchorYs.dropFirst().map { $0 - 40 }
        var parts = Array(repeating: [OCRBoxItem](), count: bounds.count + 1)
        for w in c {
            var k = 0
            for (bi, b) in bounds.enumerated() where w.y >= b { k = bi + 1 }
            parts[k].append(w)
        }
        return parts.filter { $0.count >= 10 }
    }
}

fileprivate func < (l: (Double, Double), r: (Double, Double)) -> Bool { l.0 != r.0 ? l.0 < r.0 : l.1 < r.1 }

// MARK: - 2. CUI hardened (înlocuiește isValidCUI + logica din CuiExtractorAgent)

enum CUI {

    /// MIN 4 CIFRE (nu 2!) — cu 2 cifre checksum-ul validează "25", "19", "21" etc.
    static func isValid(_ cui: String) -> Bool {
        guard cui.count >= 4, cui.count <= 10, Int(cui) != nil else { return false }
        let key = Array("753217532".reversed())
        let digits = Array(cui.reversed())
        guard let control = digits.first?.wholeNumberValue else { return false }
        var sum = 0
        for i in 1..<digits.count where i - 1 < key.count {
            sum += (digits[i].wholeNumberValue ?? 0) * (key[i - 1].wholeNumberValue ?? 0)
        }
        var calc = (sum * 10) % 11
        if calc == 10 { calc = 0 }
        return calc == control
    }

    /// Reparare de cifre pt. confuzii OCR frecvente (O→0, I→1, S→5, B→8, @→0 ...)
    static func repairOCRDigits(_ s: String) -> String {
        let subs: [Character: Character] = ["O": "0", "Q": "0", "D": "0", "I": "1", "L": "1",
                                            "|": "1", "Z": "2", "S": "5", "B": "8", "G": "6", "@": "0"]
        return String(s.uppercased().map { subs[$0] ?? $0 })
    }

    /// Extrage candidații CUI dintr-un bon:
    ///  - DOAR cu context (COD FISCAL / C.I.F. / CUI / prefix RO)
    ///  - NICIODATĂ de pe linii cu CLIENT / CNP / BENEF / CUMPARATOR (acolo e CUI-ul cumpărătorului)
    ///  - dacă checksum-ul nu trece direct, generează variante cu o cifră reparată/adăugată
    ///    → toate variantele se verifică ÎNTR-UN SINGUR batch ANAF, iar fuzzy match-ul
    ///    pe denumire alege candidatul corect.
    static func candidates(fromLines lines: [String], buyerCui: String?) -> (best: String?, verified: Bool, anafCandidates: [String]) {
        let normalizedBuyerCui = buyerCui.map { repairOCRDigits($0).filter { $0.isNumber } }
        let buyerRegex = try! NSRegularExpression(pattern: "CLIENT|CUMPARATOR|BENEF|CNP")
        let ctxRegex = try! NSRegularExpression(
            pattern: "(?:COD\\s*FISCAL|COD\\s*IDENTIFICARE\\s*FISCALA|C\\.?\\s*[I1]\\.?\\s*F|CUI)\\s*[.:]?\\s*(?:R[O0Q])?\\s*[.:]?\\s*([A-Z0-9@]{4,10})|\\bR[O0]\\s?([0-9OQDILSZB@]{4,10})\\b",
            options: [.caseInsensitive])

        var raw: [String] = []
        for line in lines {
            let upper = line.uppercased()
            let range = NSRange(upper.startIndex..., in: upper)
            if buyerRegex.firstMatch(in: upper, range: range) != nil { continue }
            for m in ctxRegex.matches(in: upper, range: range) {
                for g in 1...2 where m.range(at: g).location != NSNotFound {
                    raw.append((upper as NSString).substring(with: m.range(at: g)))
                }
            }
        }

        // 1) match direct pe checksum
        for c in raw {
            let d = repairOCRDigits(c).filter { $0.isNumber }
            if isValid(d), d != normalizedBuyerCui { return (d, true, [d]) }
        }
        // 2) reparare ghidată de checksum → candidați pentru batch-ul ANAF
        var anafCandidates: [String] = []
        for c in raw {
            let d = repairOCRDigits(c).filter { $0.isNumber }
            guard d.count >= 4 else { continue }
            for x in "0123456789" where isValid(d + String(x)) { anafCandidates.append(d + String(x)) }
            let chars = Array(d)
            for pos in 0..<chars.count {
                for x in "0123456789" where chars[pos] != x {
                    var v = chars; v[pos] = x
                    let s = String(v)
                    if isValid(s) { anafCandidates.append(s) }
                }
            }
        }
        var seen = Set<String>()
        anafCandidates = anafCandidates.filter { $0 != normalizedBuyerCui && seen.insert($0).inserted }
        return (anafCandidates.first, false, anafCandidates)
    }
}

// MARK: - 3. ANAF v9 — batch + fuzzy match pe denumire (înlocuiește verifyWithANAF)

struct ANAFCompany {
    let cui: String
    let denumire: String?
    let adresa: String?
    let scpTVA: Bool?
}

enum ANAF {
    /// v8 e depășit. v9: URL nou + JSON restructurat (date_generale / inregistrare_scop_Tva).
    /// Limite: ~100 CUI-uri/request, 1 request/secundă → UN SINGUR batch pentru toată poza.
    static let endpoint = URL(string: "https://webservicesp.anaf.ro/api/PlatitorTvaRest/v9/tva")!

    static func verifyBatch(cuis: [String]) async -> [String: ANAFCompany] {
        guard !cuis.isEmpty else { return [:] }
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let payload = cuis.prefix(100).map { ["cui": $0, "data": today] }
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return [:] }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let found = json["found"] as? [[String: Any]] else { return [:] }

        var out: [String: ANAFCompany] = [:]
        for f in found {
            let dg = f["date_generale"] as? [String: Any] ?? [:]
            let cuiInt = (dg["cui"] as? Int) ?? (dg["cui"] as? String).flatMap(Int.init) ?? 0
            let cuiStr = String(cuiInt)
            guard cuiInt > 0 else { continue }
            let tva = (f["inregistrare_scop_Tva"] as? [String: Any])?["scpTVA"] as? Bool
            out[cuiStr] = ANAFCompany(cui: cuiStr, denumire: dg["denumire"] as? String,
                                     adresa: dg["adresa"] as? String, scpTVA: tva)
        }
        return out
    }

    /// Similaritate pe tokenuri între denumirea ANAF și antetul OCR (rezolvă și repararea de cifre:
    /// dintre candidații CUI, câștigă cel a cărui denumire oficială seamănă cu antetul bonului).
    static func nameMatchScore(anafName: String, ocrHeader: String) -> Double {
        func tokens(_ s: String) -> Set<String> {
            Set(s.uppercased()
                 .replacingOccurrences(of: "[^A-Z0-9 ]", with: " ", options: .regularExpression)
                 .split(separator: " ")
                 .map(String.init)
                 .filter { $0.count > 2 && !["SRL", "THE"].contains($0) })
        }
        let a = tokens(anafName), b = tokens(ocrHeader)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(min(a.count, b.count))
    }
}

// MARK: - 4. Cote TVA România, date-aware (Legea 141/2025)

enum RomanianVAT {
    /// Cotele valide în funcție de DATA documentului:
    ///  - de la 01.08.2025: 21% standard, 11% redusă (5% și 9% eliminate)
    ///  - 9% doar tranzitoriu pentru locuințe până la 31.07.2026 (nu apare pe bonuri de casă)
    ///  - înainte de 01.08.2025: 19%, 9%, 5%
    static func validRates(documentDate: Date?) -> [Double] {
        guard let d = documentDate else { return [21, 11, 19, 9, 5] }
        let cal = Calendar(identifier: .gregorian)
        let switchDate = cal.date(from: DateComponents(year: 2025, month: 8, day: 1))!
        let housingEnd = cal.date(from: DateComponents(year: 2026, month: 7, day: 31))!
        if d >= switchDate {
            return d <= housingEnd ? [21, 11, 9] : [21, 11]
        }
        return [19, 9, 5]
    }

    /// Un bon din 2026 cu cota 19% = aproape sigur eroare OCR → avertisment.
    static func warningForRate(_ rate: Double, documentDate: Date?) -> String? {
        guard let d = documentDate, !validRates(documentDate: d).contains(rate) else { return nil }
        return "Cota TVA \(Int(rate))% nu era în vigoare la data documentului — posibilă eroare OCR."
    }
}

// MARK: - 5. Sume: blacklist de context + validare/corecție matematică
//          (înlocuiește fallback-ul "cel mai mare număr" — sursa totalurilor de miliarde)

enum FinancialExtraction {

    /// Liniile cu aceste cuvinte NU conțin sume de bani (ID-uri, autorizații, carduri):
    static let amountBlacklist = try! NSRegularExpression(
        pattern: "RC\\s*:|AUTOR|NR\\.?\\s*CARD|TRX|CNP|C\\.?I\\.?F|TELEFON|POS\\b|EJTRZ|ID\\s*UNIC",
        options: [.caseInsensitive])

    /// Sumele au OBLIGATORIU formatul \d{1,5}[.,]\d{2}. Un număr fără separator zecimal
    /// (4000884157, 30630040) nu e niciodată un total.
    static let amountRegex = try! NSRegularExpression(pattern: "(?<![\\d%])(\\d{1,5})\\s?[.,]\\s?(\\d{2})(?!\\d)")

    static func amounts(in line: String) -> [Double] {
        let range = NSRange(line.startIndex..., in: line)
        guard amountBlacklist.firstMatch(in: line, range: range) == nil else { return [] }
        return amountRegex.matches(in: line, range: range).compactMap { m in
            let i = (line as NSString).substring(with: m.range(at: 1))
            let f = (line as NSString).substring(with: m.range(at: 2))
            return Double("\(i).\(f)")
        }
    }

    /// Validare + CORECȚIE matematică bidirecțională:
    ///  - dacă (total, tva) sunt consistente cu cota → verified
    ///  - dacă nu: derivează totalul din TVA (total = tva × (100+r)/r) și acceptă-l
    ///    DOAR dacă suma derivată chiar apare pe bon (cazul real: OCR a citit 188,75,
    ///    TVA 31,37 la 21% → 180,75, care există pe bon → totalul corect e 180,75).
    ///  - invers: dacă lipsește TVA-ul, calculează-l din total și marchează.
    static func reconcile(total: Double?, vat: Double?, rate: Double,
                          allAmountsOnReceipt: [Double]) -> (total: Double?, vat: Double?, verified: Bool, warning: String?) {
        func consistent(_ t: Double, _ v: Double) -> Bool { abs(v - t * rate / (100 + rate)) <= 0.06 }

        if let t = total, let v = vat, consistent(t, v) { return (t, v, true, nil) }

        if let v = vat {
            let tCalc = (v * (100 + rate) / rate * 100).rounded() / 100
            if let match = allAmountsOnReceipt.first(where: { abs($0 - tCalc) <= 0.06 }) {
                let warn = (total != nil && abs(total! - match) > 0.06)
                    ? "Total corectat matematic din TVA: \(total!) → \(match)" : nil
                return (match, v, true, warn)
            }
            if let t = total {
                let vCalc = (t * rate / (100 + rate) * 100).rounded() / 100
                return (t, vCalc, false, "TVA recalculat din total (valoarea OCR nu era consistentă)")
            }
        }
        if let t = total, vat == nil {
            let vCalc = (t * rate / (100 + rate) * 100).rounded() / 100
            return (t, vCalc, false, "TVA calculat matematic din total")
        }
        return (total, vat, false, nil)
    }
}

// MARK: - 6. Sugestii conturi contabile

enum AccountSuggestion {
    static func suggest(fullText: String) -> (account: String, note: String?) {
        let t = fullText.uppercased()
        if t.range(of: "MOTORINA|BENZINA|GPL|DIESEL|OMV|PETROM|\\bMOL\\b|ROMPETROL|GAZ SRL",
                   options: .regularExpression) != nil {
            return ("6022 Combustibili (sau 3022 dacă se stochează)",
                    "TVA deductibilă 50% dacă vehiculul nu este utilizat exclusiv în scop economic (art. 298 CF); 100% cu foaie de parcurs.")
        }
        if t.range(of: "PARFUMERIE|DOUGLAS|SEPHORA|CADOU", options: .regularExpression) != nil {
            return ("623 Protocol (sau 6588 Alte cheltuieli)", "Protocol: deductibilitate limitată la impozitul pe profit.")
        }
        if t.range(of: "RESTAURANT|CATERING|CAFENEA|PIZZA", options: .regularExpression) != nil {
            return ("623 Protocol", "Atenție: pe același bon mâncarea e la 11%, alcoolul la 21%.")
        }
        if t.range(of: "PAPETARIE|BIROTICA|EMAG|ALTEX", options: .regularExpression) != nil {
            return ("604 Materiale nestocate / 303 Obiecte de inventar", nil)
        }
        return ("628 Alte servicii / 604 Materiale nestocate", "Necesită încadrare manuală.")
    }
}

// MARK: - Integrare în processOcrResult (schiță)
//
//  let receipts = ReceiptSegmenter.segment(wordBoxes)          // 2. segmentare
//  var allCandidates: [String] = []
//  var perReceipt: [(lines: [String], cuiResult: ...)] = []
//  for r in receipts {
//      let lines = groupIntoLines(r)                            // pe clusterul DEJA separat
//      let cui = CUI.candidates(fromLines: lines, buyerCui: buyerCui)
//      allCandidates += cui.anafCandidates
//      ...extrage nr. bon, dată, firma, total, tva...
//  }
//  let anaf = await ANAF.verifyBatch(cuis: allCandidates)       // UN singur request
//  // per bon: alege candidatul cu ANAF.nameMatchScore maxim față de antetul OCR;
//  // la match > 0.5: cuiRequiresVerification = false și suprascrie companyName cu denumirea ANAF.
