//
//  VaporServer.swift
//  OcrServer
//
//  Created by Riddle Ling on 2025/8/21.
//

import Vapor
import Vision

public struct OCRRectItem: Content {
    let topLeft_x: Double
    let topLeft_y: Double
    let topRight_x: Double
    let topRight_y: Double
    let bottomLeft_x: Double
    let bottomLeft_y: Double
    let bottomRight_x: Double
    let bottomRight_y: Double
}

public struct OCRBoxItem: Content {
    let text: String
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    let rect: OCRRectItem?
}

struct OCRResult: Content {
    let text: String
    let image_width: Int
    let image_height: Int
    let boxes: [OCRBoxItem]
}

struct DocOCRResult: Content {
    let success: Bool
    let message: String
    let ocr_text: String
}

struct UploadResponse: Content {
    let success: Bool
    let message: String
    let ocr_result: String
    let image_width: Int
    let image_height: Int
    let ocr_boxes: [OCRBoxItem]
    var accounting_data: AccountingResult? = nil
    var accounting_data_array: [AccountingResult]? = nil
}

actor VaporServer {
    private var app: Application?
    private var runTask: Task<Void, Never>?
    
    // 自動重啟設定
    private var shouldAutoRestart = true
    
    // 當伺服器停止時發通知
    private var onStopped: (@Sendable () -> Void)?

    let host: String = "0.0.0.0"
    let environment: Environment = .production
    
    // 可由外部設置
    var port: Int = 8000

    // OCR 參數
    var recognitionLevel: RecognizeTextRequest.RecognitionLevel = .accurate
    var usesLanguageCorrection: Bool = true
    var automaticallyDetectsLanguage: Bool = true

    private(set) var isRunning: Bool = false

    // MARK: - Public API

    // 設定停止時回呼
    func setOnStopped(_ handler: @escaping @Sendable () -> Void) {
        self.onStopped = handler
    }
    
    // 開關自動重啟
    func setAutoRestart(_ enabled: Bool) {
        self.shouldAutoRestart = enabled
    }

    func start() async throws {
        guard runTask == nil else { return } // 已在跑就不重複啟動

        let app = try await Application.make(environment)
        app.http.server.configuration.hostname = host
        app.http.server.configuration.port = port

        let corsConfiguration = CORSMiddleware.Configuration(
            allowedOrigin: .all,
            allowedMethods: [.GET, .POST, .PUT, .OPTIONS, .DELETE, .PATCH],
            allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith, .userAgent, .accessControlAllowOrigin]
        )
        let cors = CORSMiddleware(configuration: corsConfiguration)
        app.middleware.use(cors, at: .beginning)

        try routes(app)

        self.app = app
        isRunning = true

        // 用 Task 背景執行事件迴圈
        runTask = Task { [weak app, weak self] in
            guard let self = self else { return }
            var hadError = false
            do {
                try await app?.execute()
            } catch {
                hadError = true
            }
            
            // 通知外界「已停止」
            if let cb = await self.onStopped { cb() }
            
            // 依設定自動重啟
            if await self.shouldAutoRestart && hadError {
                await self.cleanupAfterStop()
                NotificationCenter.default.post(
                    name: .vaporServerShouldRestart,
                    object: nil,
                    userInfo: ["reason": "crash"]
                )
            }
        }
    }

    func stop() async {
        guard let app = app else { return }
        try? await app.asyncShutdown()   // 非同步關閉
        self.cleanupAfterStop()
    }

    func restart() async throws {
        await stop()
        try await start()
    }
    
    func running() -> Bool { isRunning }
    
    func configure(
        port: Int? = nil,
        recognitionLevel: RecognizeTextRequest.RecognitionLevel? = nil,
        usesLanguageCorrection: Bool? = nil,
        automaticallyDetectsLanguage: Bool? = nil,
    ) {
        if let v = port { self.port = v }
        if let v = recognitionLevel { self.recognitionLevel = v }
        if let v = usesLanguageCorrection { self.usesLanguageCorrection = v }
        if let v = automaticallyDetectsLanguage { self.automaticallyDetectsLanguage = v }
    }
    
    // MARK: - Cleanup After Stop
    
    private func cleanupAfterStop() {
        //runTask?.cancel()
        runTask = nil
        app = nil
        isRunning = false
    }

    // MARK: - Routes

    private func routes(_ app: Application) throws {
        // GET /ping
        app.get("ping") { req async throws -> Response in
            var headers = HTTPHeaders()
            headers.add(name: .contentType, value: "application/json")
            return Response(status: .ok, headers: headers, body: .init(string: "{\"status\":\"ok\"}"))
        }
        
        // GET /
        app.get { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.internalServerError) }

            // 從 actor 讀取屬性要 await
            let port = await self.port
            
            var docOcrCheckBox = ""
            var docOcrApiPre = ""
            if #available(iOS 26, *) {
                docOcrCheckBox = """
                <div>
                    <input type="checkbox" id="docOcr" name="docOcr"/>
                    <label for="docOcr">Document Paragraph Detection</label>
                </div><br>
                """
                
                docOcrApiPre = """
                OR
                <h3>Upload an image via <code>docOCR</code> API:</h3>
                <pre><code>curl -H "Accept: application/json" \\
                  -X POST http://&lt;YOUR IP&gt;:\(port)/docOCR \\
                  -F "file=@01.png"</code></pre>
                """
            } else {
                docOcrCheckBox = ""
                docOcrApiPre = ""
            }

            let html = """
            <!doctype html>
            <html>
            <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <title>OCR Server</title>
                <style>
                    code {
                        background: #dadada;
                        padding: 2px 6px;
                        font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
                        font-size: 0.85em;
                        font-weight: 600;
                        border-radius: 5px;
                    }
                    pre {
                        background: #dadada;
                        padding: 16px;
                        overflow: auto;
                        font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
                        font-size: 0.85em;
                        line-height: 1.45;
                        border-radius: 5px;
                    }
                    pre code {
                        background: transparent;
                        padding: 0;
                        font-size: inherit;
                        color: inherit;
                        font-weight: normal;
                    }
                </style>
            </head>
            <body>
                <h1>OCR Server</h1>
                <h3>Upload an image via <code>upload</code> API:</h3>
                <pre><code>curl -H "Accept: application/json" \\
              -X POST http://&lt;YOUR IP&gt;:\(port)/upload \\
              -F "file=@01.png"</code></pre>
                \(docOcrApiPre)
                <hr>
                <h3>OCR Test:</h3>
                <form id="ocrForm" action="/upload" method="post" enctype="multipart/form-data">
                    \(docOcrCheckBox)
                    <label>
                        Choose file:
                        <input type="file" name="file" required>
                    </label>
                    <br><br>
                    <input type="submit" value="Upload file">
                </form>
            </body>
            <script>
                const form = document.getElementById("ocrForm");
                const docOcr = document.getElementById("docOcr");

                form.addEventListener("submit", function () {
                    if (docOcr && docOcr.checked) {
                        form.action = "/docOCR";
                    } else {
                        form.action = "/upload";
                    }
                });
            </script>
            </html>
            """
            return Self.htmlResponse(html)
        }

        // POST /upload（限制收集本文大小，可自行調整）
        app.on(.POST, "upload", body: .collect(maxSize: "100mb")) { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.internalServerError) }

            struct Upload: Content { 
                var file: File 
                var buyer_cui: String?
            }

            let upload: Upload
            do {
                upload = try req.content.decode(Upload.self)
            } catch {
                return try Self.jsonResponse(
                    .badRequest,
                    UploadResponse(
                        success: false,
                        message: "Missing or empty 'file' part",
                        ocr_result: "",
                        image_width: 0,
                        image_height: 0,
                        ocr_boxes: []
                    )
                )
            }

            guard upload.file.data.readableBytes > 0 else {
                return try Self.jsonResponse(
                    .badRequest,
                    UploadResponse(
                        success: false,
                        message: "Missing or empty 'file' part",
                        ocr_result: "",
                        image_width: 0,
                        image_height: 0,
                        ocr_boxes: []
                    )
                )
            }

            // 取得 actor 內的參數（需 await）
            let recognitionLevel = await self.recognitionLevel
            let usesLanguageCorrection = await self.usesLanguageCorrection
            let automaticallyDetectsLanguage = await self.automaticallyDetectsLanguage

            // ByteBuffer -> Data
            let data = Self.byteBufferToData(upload.file.data)

            // OCR
            let textRecognizer = TextRecognizer(
                recognitionLevel: recognitionLevel,
                usesLanguageCorrection: usesLanguageCorrection,
                automaticallyDetectsLanguage: automaticallyDetectsLanguage
            )

            let accept = (req.headers.first(name: .accept) ?? "").lowercased()
            
            let result = await textRecognizer.getOcrResult(data: data)
            
            var accountingData: AccountingResult? = nil
            var accountingDataArray: [AccountingResult] = []
            
            if let boxes = result?.boxes, !boxes.isEmpty {
                print("===== OCR DEBUG =====")
                print("Total OCR boxes: \(boxes.count)")
                
                // Print all boxes that contain CUI-related keywords
                for box in boxes {
                    let upper = box.text.uppercased()
                    if upper.contains("CIF") || upper.contains("CUI") || upper.contains("FISCAL") || upper.contains("RO") {
                        print("  CUI-box: '\(box.text)' at x=\(Int(box.x)) y=\(Int(box.y)) w=\(Int(box.w)) h=\(Int(box.h))")
                    }
                    if upper.contains("TOTAL") {
                        print("  TOTAL-box: '\(box.text)' at x=\(Int(box.x)) y=\(Int(box.y))")
                    }
                    if upper.contains("TVA") {
                        print("  TVA-box: '\(box.text)' at x=\(Int(box.x)) y=\(Int(box.y))")
                    }
                }
                
                let clusters = AccountingOrchestrator.shared.clusterBoxes(boxes)
                print("Clusters found: \(clusters.count)")
                for (i, cluster) in clusters.enumerated() {
                    print("  Cluster \(i): \(cluster.count) boxes")
                    let clusterText = cluster.prefix(5).map { "'\($0.text)'" }.joined(separator: ", ")
                    print("    First boxes: \(clusterText)")
                }
                
                for cluster in clusters {
                    let clusterResults = await AccountingOrchestrator.shared.processOcrResult(boxes: cluster, buyerCui: upload.buyer_cui)
                    print("  -> Produced \(clusterResults.count) results: CUI=\(clusterResults.first?.cui ?? "nil"), Total=\(clusterResults.first?.totalAmount ?? 0), TVA=\(clusterResults.first?.vatAmount ?? 0)")
                    accountingDataArray.append(contentsOf: clusterResults)
                }
                
                print("Total accounting results: \(accountingDataArray.count)")
                print("===== END DEBUG =====")
                
                // Pentru compatibilitate backward, primul element e in accountingData
                accountingData = accountingDataArray.first
            }
            
            if result == nil && accept.contains("application/json") {
                return try Self.jsonResponse(.internalServerError, UploadResponse(success: false,
                                                                                  message: "OCR failed",
                                                                                  ocr_result: "",
                                                                                  image_width: 0,
                                                                                  image_height: 0,
                                                                                  ocr_boxes: []))
            }
            
            if accept.contains("application/json") {
                return try Self.jsonResponse(
                    .ok,
                    UploadResponse(
                        success: true,
                        message: "File uploaded successfully",
                        ocr_result: result?.text ?? "",
                        image_width: result?.image_width ?? 0,
                        image_height: result?.image_height ?? 0,
                        ocr_boxes: result?.boxes ?? [],
                        accounting_data: accountingData,
                        accounting_data_array: accountingDataArray
                    )
                )
            } else {
                let escaped = Self.htmlEscape(result?.text ?? "")
                let html = """
                <!doctype html>
                <html>
                <head>
                    <meta charset="utf-8">
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                    <title>OCR Server</title>
                </head>
                <body>
                    <h2>OCR Result:</h2>
                    <pre>\(escaped)</pre>
                </body>
                </html>
                """
                return Self.htmlResponse(html)
            }
        }
        
        // POST /docOCR（限制收集本文大小，可自行調整）
        app.on(.POST, "docOCR", body: .collect(maxSize: "100mb")) { [weak self] req async throws -> Response in
            if #unavailable(iOS 26) {
                // iOS 26 以下
                return try Self.jsonResponse(
                    .ok,
                    DocOCRResult(
                        success: false,
                        message: "This API is only supported on iOS 26 and later",
                        ocr_text: ""
                    )
                )
            }
            
            guard let self else { throw Abort(.internalServerError) }

            struct Upload: Content { var file: File }

            let upload: Upload
            do {
                upload = try req.content.decode(Upload.self)
            } catch {
                return try Self.jsonResponse(
                    .badRequest,
                    DocOCRResult(
                        success: false,
                        message: "Missing or empty 'file' part",
                        ocr_text: ""
                    )
                )
            }

            guard upload.file.data.readableBytes > 0 else {
                return try Self.jsonResponse(
                    .badRequest,
                    DocOCRResult(
                        success: false,
                        message: "Missing or empty 'file' part",
                        ocr_text: ""
                    )
                )
            }

            // 取得 actor 內的參數（需 await）
            _ = await self.usesLanguageCorrection
            _ = await self.automaticallyDetectsLanguage

            // ByteBuffer -> Data
            let data = Self.byteBufferToData(upload.file.data)

            let accept = (req.headers.first(name: .accept) ?? "").lowercased()
            
            // OCR
            var resultText : String? = nil
            // DocRecognizer is currently unsupported on this SDK version.
            if resultText == nil && accept.contains("application/json") {
                return try Self.jsonResponse(.internalServerError, DocOCRResult(success: false,
                                                                                message: "OCR failed",
                                                                                ocr_text: ""))
            }
            
            if accept.contains("application/json") {
                return try Self.jsonResponse(
                    .ok,
                    DocOCRResult(
                        success: true,
                        message: "OCR completed successfully",
                        ocr_text: resultText ?? ""
                    )
                )
            } else {
                let escaped = Self.htmlEscape(resultText ?? "")
                let html = """
                <!doctype html>
                <html>
                <head>
                    <meta charset="utf-8">
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                    <title>OCR Server</title>
                    <style>
                        pre {
                            width: 100%;
                            max-width: 100%;
                            box-sizing: border-box;
                            white-space: pre-wrap;
                            word-wrap: break-word;
                            overflow-wrap: break-word;
                        }
                    </style>
                </head>
                <body>
                    <h2>OCR Result:</h2>
                    <hr>
                    <pre>\(escaped)</pre>
                </body>
                </html>
                """
                return Self.htmlResponse(html)
            }
        }
    }

    // MARK: - Helpers

    private static func byteBufferToData(_ buffer: ByteBuffer) -> Data {
        var tmp = buffer
        if let bytes = tmp.readBytes(length: tmp.readableBytes) {
            return Data(bytes)
        }
        return Data()
    }

    private static func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func htmlResponse(_ html: String, status: HTTPResponseStatus = .ok) -> Response {
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "text/html; charset=utf-8")
        return Response(status: status, headers: headers, body: .init(string: html))
    }

    private static func jsonResponse<T: Content>(_ status: HTTPResponseStatus, _ payload: T) throws -> Response {
        let res = Response(status: status)
        try res.content.encode(payload, as: .json)
        return res
    }
}

extension Notification.Name {
    static let vaporServerShouldRestart = Notification.Name("vaporServerShouldRestart")
}

// MARK: - Accounting Extraction (Contabilitate)

public struct VatBreakdown: Content {
    public var percentage: String
    public var vatAmount: Double
    public var baseAmount: Double
}

public struct AccountingResult: Content {
    public var documentType: String?
    public var documentTypeRequiresVerification: Bool = true
    
    public var documentSeries: String?
    public var documentNumber: String?
    public var documentDate: String?
    
    public var cui: String?
    public var cuiRequiresVerification: Bool = true
    public var companyName: String?
    public var companyAddress: String?
    public var companyIsVatPayer: Bool?
    
    public var totalAmount: Double?
    public var totalRequiresVerification: Bool = true
    
    public var vatAmount: Double?
    public var vatRequiresVerification: Bool = true
    
    public var vatPercentages: String?
    
    public var baseAmount: Double?
    
    public var vatBreakdowns: [VatBreakdown]?
    
    public var fiscalWarnings: [String] = []
    
    public var globalRequiresManualVerification: Bool {
        return documentTypeRequiresVerification || cuiRequiresVerification || totalRequiresVerification || vatRequiresVerification || !fiscalWarnings.isEmpty
    }
}

protocol AccountingAgent {
    func process(textBlocks: [String], boxes: [OCRBoxItem], result: inout AccountingResult) async
}

class DocumentClassificationAgent: AccountingAgent {
    func process(textBlocks: [String], boxes: [OCRBoxItem], result: inout AccountingResult) async {
        let fullText = textBlocks.joined(separator: " ").uppercased()
        
        let hasPOS = fullText.contains("TERMINAL ID") || fullText.contains("PIN VERIFICAT") || fullText.contains("TRANZACTIE ACCEPTATA") || fullText.contains("TRANZACTIE APROBATA") || fullText.contains("POS")
        
        if fullText.contains("FACTURA") || fullText.contains("INVOICE") {
            result.documentType = "Factură"
            result.documentTypeRequiresVerification = false
        } else if fullText.contains("BON FISCAL") || fullText.contains("CASA DE MARCAT") || fullText.contains("BF.") || fullText.contains("BF ") {
            result.documentType = "Bon Fiscal"
            result.documentTypeRequiresVerification = false
        } else if hasPOS {
            result.documentType = "Chitanță POS"
            result.documentTypeRequiresVerification = false
        } else if fullText.contains("CHITANTA") {
            result.documentType = "Chitanță de mână"
            result.documentTypeRequiresVerification = false
        } else if fullText.contains("BENZINA") || fullText.contains("MOTORINA") || fullText.contains("DIESEL") {
            result.documentType = "Fișă Combustibil"
            result.documentTypeRequiresVerification = false
        } else {
            result.documentType = "Necunoscut"
            result.documentTypeRequiresVerification = true
        }
    }
}

class DocumentDetailsAgent: AccountingAgent {
    func process(textBlocks: [String], boxes: [OCRBoxItem], result: inout AccountingResult) async {
        let fullText = textBlocks.joined(separator: "\n").uppercased()
        
        let seriesPattern = "(?:SERIA|SERIE|SERIA:|CHITANTA\\s*SERIA)\\s*([A-Z]{1,5})"
        if let regex = try? NSRegularExpression(pattern: seriesPattern, options: []) {
            let nsString = fullText as NSString
            let match = regex.firstMatch(in: fullText, options: [], range: NSRange(location: 0, length: nsString.length))
            if let m = match, m.numberOfRanges > 1 {
                result.documentSeries = nsString.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        let numberPattern = "(?:NR\\.?|NUMAR|BON\\s*NR\\.?|FACTURA\\s*NR\\.?|CHITANTA\\s*NR\\.?|BF\\.?)\\s*[:]*\\s*([0-9]{1,10})"
        if let regex = try? NSRegularExpression(pattern: numberPattern, options: []) {
            let nsString = fullText as NSString
            let match = regex.firstMatch(in: fullText, options: [], range: NSRange(location: 0, length: nsString.length))
            if let m = match, m.numberOfRanges > 1 {
                result.documentNumber = nsString.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        let datePattern = "(?:DATA\\s*[:]*\\s*)?([0-3][0-9][\\.\\-\\/][0-1][0-9][\\.\\-\\/]20[0-9]{2})"
        if let regex = try? NSRegularExpression(pattern: datePattern, options: []) {
            let nsString = fullText as NSString
            let match = regex.firstMatch(in: fullText, options: [], range: NSRange(location: 0, length: nsString.length))
            if let m = match, m.numberOfRanges > 1 {
                result.documentDate = nsString.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
}

class CuiExtractorAgent: AccountingAgent {
    func process(textBlocks: [String], boxes: [OCRBoxItem], result: inout AccountingResult) async {
        // Helper checking if a box represents a buyer
        func isBuyerBox(_ box: OCRBoxItem) -> Bool {
            let cleanText = box.text.uppercased().replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
            let buyerKeywords = ["CLIENT", "CUMP", "BENEF", "CNP"]
            for kw in buyerKeywords {
                if cleanText.contains(kw) { return true }
            }
            return false
        }

        let sortedHeights = boxes.map { $0.h }.sorted()
        let medianHeight = sortedHeights.isEmpty ? 15.0 : CGFloat(sortedHeights[sortedHeights.count / 2])

        // 1. Cautare Spatiala Inteligenta 2D (Fuzzy)
        let cuiKeywords = ["CIF", "CUI", "CODFISCAL", "RO"]
        var candidateBoxes: [OCRBoxItem] = []
        
        for box in boxes {
            let cleanText = box.text.uppercased().replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
            
            if isBuyerBox(box) {
                continue
            }
            
            if cuiKeywords.contains(where: { cleanText.contains($0) || (cleanText.count <= $0.count + 2 && cleanText.isFuzzyMatch($0, tolerance: 1)) }) {
                candidateBoxes.append(box)
            }
        }
        
        // Verificam textul din interiorul cutiilor gasite (poate CUI-ul e in aceeasi cutie: "CIF RO123456")
        for box in candidateBoxes {
            if box.text.contains("%") { continue }
            let text = box.text.uppercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ".", with: "")
            let numbersOnly = text.filter { $0.isNumber }
            if isValidCUI(cui: numbersOnly) {
                result.cui = numbersOnly
                result.cuiRequiresVerification = false
                await verifyWithANAF(cui: numbersOnly, result: &result)
                result.cui = numbersOnly 
                return
            }
        }
        
        // Cautam cutii la dreapta sau putin mai jos
        for keywordBox in candidateBoxes {
            let nearbyBoxes = boxes.filter {
                ($0.x != keywordBox.x || $0.y != keywordBox.y) && // exclude self
                $0.y >= keywordBox.y - keywordBox.h * 0.8 && $0.y <= keywordBox.y + keywordBox.h * 2.0 &&
                $0.x >= keywordBox.x - keywordBox.w * 0.5
            }.sorted { $0.x < $1.x }
            
            for nb in nearbyBoxes {
                if nb.text.contains("%") { continue }
                let text = nb.text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ".", with: "")
                let numbersOnly = text.filter { $0.isNumber }
                if !numbersOnly.isEmpty && isValidCUI(cui: numbersOnly) {
                    result.cui = numbersOnly
                    result.cuiRequiresVerification = false
                    await verifyWithANAF(cui: numbersOnly, result: &result)
                    result.cui = numbersOnly
                    return
                }
            }
        }
        
        // 2. Fallback la Regex-ul clasic
        let fullText = textBlocks.joined(separator: " ").uppercased()
        let fallbackPattern = "\\b([0-9]{2,10})\\b"
        if let regex = try? NSRegularExpression(pattern: fallbackPattern, options: []) {
            let nsString = fullText as NSString
            let results = regex.matches(in: fullText, options: [], range: NSRange(location: 0, length: nsString.length))
            
            for match in results {
                if match.numberOfRanges > 1 {
                    let cuiCandidate = nsString.substring(with: match.range(at: 1))
                    if isValidCUI(cui: cuiCandidate) {
                        result.cui = cuiCandidate
                        result.cuiRequiresVerification = false
                        await verifyWithANAF(cui: cuiCandidate, result: &result)
                        result.cui = cuiCandidate
                        return
                    }
                }
            }
        }
        
        // 3. Fallback: extractia de secvente alfanumerice din vecinatate (lungime 2-12)
        print("[CUI Extraction] No mathematically valid CUI found. Attempting fallback for inaccurate OCR...")
        
        func cleanCandidate(_ rawText: String) -> String? {
            var s = String(rawText.uppercased().filter { $0.isLetter || $0.isNumber })
            let prefixes = ["CIF", "CUI", "RO", "R0", "COD", "FISCAL", "CODFISCAL"]
            var changed = true
            while changed {
                changed = false
                for prefix in prefixes {
                    if s.hasPrefix(prefix) {
                        s = String(s.dropFirst(prefix.count))
                        changed = true
                    }
                }
            }
            if s.count >= 2 && s.count <= 12 && s.contains(where: { $0.isNumber }) {
                return s
            }
            return nil
        }
        
        var fallbackCandidates: [(text: String, distance: Double)] = []
        
        for box in candidateBoxes {
            if let cleaned = cleanCandidate(box.text) {
                fallbackCandidates.append((text: cleaned, distance: 0.0))
            }
        }
        
        for keywordBox in candidateBoxes {
            let nearbyBoxes = boxes.filter {
                ($0.x != keywordBox.x || $0.y != keywordBox.y) &&
                $0.y >= keywordBox.y - keywordBox.h * 1.5 && $0.y <= keywordBox.y + keywordBox.h * 3.0 &&
                $0.x >= keywordBox.x - keywordBox.w * 0.5
            }
            for nb in nearbyBoxes {
                if nb.text.contains("%") { continue }
                if let cleaned = cleanCandidate(nb.text) {
                    let dx = nb.x - keywordBox.x
                    let dy = nb.y - keywordBox.y
                    let dist = sqrt(dx*dx + dy*dy)
                    fallbackCandidates.append((text: cleaned, distance: dist))
                }
            }
        }
        
        if !fallbackCandidates.isEmpty {
            let sortedCandidates = fallbackCandidates.sorted { $0.distance < $1.distance }
            let bestCandidate = sortedCandidates.first!.text
            result.cui = bestCandidate
            result.cuiRequiresVerification = true
            print("[CUI Extraction] Fallback matched candidate: '\(bestCandidate)'")
            return
        }
        
        result.cuiRequiresVerification = true
    }

    
    private func verifyWithANAF(cui: String, result: inout AccountingResult) async {
        let urlString = "https://webservicesp.anaf.ro/PlatitorTvaRest/api/v8/ws/tva"
        guard let url = URL(string: urlString) else {
            result.cuiRequiresVerification = true
            return
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: Date())
        
        let payload: [[String: Any]] = [
            [
                "cui": Int(cui) ?? 0,
                "data": dateString
            ]
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            result.cuiRequiresVerification = true
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let found = json["found"] as? [[String: Any]],
                   let firstMatch = found.first {
                    
                    result.companyName = firstMatch["denumire"] as? String
                    result.companyAddress = firstMatch["adresa"] as? String
                    result.companyIsVatPayer = firstMatch["scpTVA"] as? Bool
                    result.cuiRequiresVerification = false
                } else {
                    result.cuiRequiresVerification = true
                }
            } else {
                result.cuiRequiresVerification = true
            }
        } catch {
            // Nu stergem CUI-ul, doar marcam
            result.cuiRequiresVerification = true
        }
    }
}

class FinancialAmountsAgent: AccountingAgent {
    func process(textBlocks: [String], boxes: [OCRBoxItem], result: inout AccountingResult) async {
        let fullText = textBlocks.joined(separator: "\n").uppercased()
        
        let sortedHeights = boxes.map { $0.h }.sorted()
        let medianHeight = sortedHeights.isEmpty ? 15.0 : sortedHeights[sortedHeights.count / 2]
        
        // --- SPATIAL TOTAL EXTRACTION ---
        let totalKeywords = ["TOTAL", "SUMA", "ACHITAT"]
        var totalFound = false
        
        // Group boxes into lines
        var lines: [[OCRBoxItem]] = []
        let sortedByY = boxes.sorted { $0.y < $1.y }
        if !sortedByY.isEmpty {
            var currentLine = [sortedByY[0]]
            let yTolerance = medianHeight * 0.4
            
            for box in sortedByY.dropFirst() {
                if abs(box.y - currentLine[0].y) < yTolerance {
                    currentLine.append(box)
                } else {
                    lines.append(currentLine)
                    currentLine = [box]
                }
            }
            lines.append(currentLine)
        }
        
        for box in boxes {
            let cleanText = box.text.uppercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ":", with: "")
            if cleanText.contains("SUBTOTAL") {
                continue
            }
            if totalKeywords.contains(where: { cleanText.contains($0) || (cleanText.count <= $0.count + 2 && cleanText.isFuzzyMatch($0, tolerance: 1)) }) {
                let yTol = max(box.h * 0.6, 15.0)
                let lineBoxes = boxes.filter { b in
                    (b.x != box.x || b.y != box.y) &&
                    abs(b.y - box.y) < yTol &&
                    b.x > box.x - box.w * 0.5
                }.sorted { $0.x < $1.x }
                
                let lineText = lineBoxes.map { $0.text.uppercased() }.joined(separator: " ") + " " + box.text.uppercased()
                var checkText = lineText
                checkText = checkText.replacingOccurrences(of: "TVA INCLUS", with: "")
                checkText = checkText.replacingOccurrences(of: "TVA INCL", with: "")
                checkText = checkText.replacingOccurrences(of: "TAXE INCLUSE", with: "")
                checkText = checkText.replacingOccurrences(of: "TAXA INCLUSA", with: "")
                if checkText.contains("TVA") || checkText.contains("TAXA") || checkText.contains("TAXE") {
                    continue
                }
                
                for lBox in lineBoxes {
                    if lBox.x <= box.x { continue }
                    let sanitized = lBox.text.replacingOccurrences(of: ",", with: ".")
                    let pattern = "([0-9]+[.][0-9]{2})"
                    if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                       let match = regex.firstMatch(in: sanitized, options: [], range: NSRange(location: 0, length: sanitized.utf16.count)) {
                        let matchedString = (sanitized as NSString).substring(with: match.range(at: 1))
                        if let val = Double(matchedString) {
                            result.totalAmount = val
                            result.totalRequiresVerification = false
                            totalFound = true
                            break
                        }
                    }
                }
            }
            if totalFound { break }
        }
        
        // Fallback TOTAL
        if !totalFound {
            let totalPattern = "(?i)(?:TOTAL|SUMA|ACHITAT|REST)\\s*(?:LEI)?\\s*[:=]*\\s*([0-9]+[.,][0-9]{2})"
            if let regex = try? NSRegularExpression(pattern: totalPattern, options: []),
               let match = regex.firstMatch(in: fullText, options: [], range: NSRange(location: 0, length: fullText.utf16.count)) {
                let matchedString = (fullText as NSString).substring(with: match.range(at: 1))
                if let val = Double(matchedString.replacingOccurrences(of: ",", with: ".")) {
                    result.totalAmount = val
                    result.totalRequiresVerification = false
                    totalFound = true
                }
            }
        }
        
        // Final Fallback: largest number
        if result.totalAmount == nil {
            let pattern = "(?<!%)\\b([0-9]+[.,][0-9]{2})\\b(?!\\s*%)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsString = fullText as NSString
                let results = regex.matches(in: fullText, options: [], range: NSRange(location: 0, length: nsString.length))
                var amounts: [Double] = []
                for match in results {
                    let matchedString = nsString.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")
                    if let val = Double(matchedString), val != 24.00, val != 21.00, val != 19.00, val != 11.00, val != 9.00, val != 5.00 {
                        amounts.append(val)
                    }
                }
                amounts.sort(by: >)
                if !amounts.isEmpty {
                    result.totalAmount = amounts[0]
                    result.totalRequiresVerification = true
                }
            }
        }
        
        let isReceipt = result.documentType == "Chitanță POS" || result.documentType == "Chitanță de mână"
        
        if isReceipt {
            result.vatAmount = 0
            result.vatPercentages = "-"
            result.baseAmount = result.totalAmount
            result.vatRequiresVerification = false
        } else {
            var breakdowns: [VatBreakdown] = []
            
            for line in lines {
                let sortedLine = line.sorted { $0.x < $1.x }
                let lineText = sortedLine.map { $0.text }.joined(separator: " ")
                
                // Find percentage
                let pctPattern = "\\b([0-9]{1,2})(?:[.,][0-9]{1,2})?\\s*%"
                guard let pctRegex = try? NSRegularExpression(pattern: pctPattern, options: []),
                      let pctMatch = pctRegex.firstMatch(in: lineText, options: [], range: NSRange(location: 0, length: lineText.utf16.count)) else {
                    continue
                }
                
                let pctRange = pctMatch.range(at: 0)
                let nsLineText = lineText as NSString
                let pctMatchString = nsLineText.substring(with: pctRange)
                let cleanLineText = lineText.replacingOccurrences(of: pctMatchString, with: "")
                
                let pctStr = nsLineText.substring(with: pctMatch.range(at: 1))
                guard let rate = Double(pctStr) else { continue }
                
                // Find all other decimal numbers
                let decPattern = "\\b([0-9]+[.,][0-9]{2})\\b"
                guard let decRegex = try? NSRegularExpression(pattern: decPattern, options: []) else { continue }
                let nsCleanText = cleanLineText as NSString
                let matches = decRegex.matches(in: cleanLineText, options: [], range: NSRange(location: 0, length: nsCleanText.length))
                
                var vals: [Double] = []
                for m in matches {
                    let matchedStr = nsCleanText.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: ".")
                    if let val = Double(matchedStr) {
                        vals.append(val)
                    }
                }
                
                var vatAmount: Double? = nil
                var baseAmount: Double? = nil
                
                if vals.count >= 2 {
                    for i in 0..<vals.count {
                        for j in 0..<vals.count {
                            if i == j { continue }
                            let baseCand = vals[i]
                            let vatCand = vals[j]
                            if abs(vatCand - baseCand * (rate / 100.0)) < 0.05 {
                                vatAmount = vatCand
                                baseAmount = baseCand
                                break
                            }
                        }
                        if vatAmount != nil { break }
                    }
                    
                    if vatAmount == nil {
                        for i in 0..<vals.count {
                            for j in 0..<vals.count {
                                if i == j { continue }
                                let baseCand = vals[i]
                                let totalCand = vals[j]
                                 if abs(totalCand - baseCand * (1.0 + rate / 100.0)) < 0.05 {
                                    baseAmount = baseCand
                                    vatAmount = ((totalCand - baseCand) * 100).rounded() / 100
                                    break
                                }
                            }
                            if vatAmount != nil { break }
                        }
                    }
                    
                    if vatAmount == nil {
                        let sortedVals = vals.sorted()
                        vatAmount = sortedVals[0]
                        baseAmount = sortedVals[1]
                    }
                } else if vals.count == 1 {
                    let val = vals[0]
                    if rate == 0.0 {
                        baseAmount = val
                        vatAmount = 0.0
                    } else if let total = result.totalAmount, abs(val - total) < 0.05 {
                        baseAmount = (total / (1.0 + rate / 100.0) * 100).rounded() / 100
                        vatAmount = ((total - baseAmount!) * 100).rounded() / 100
                    } else {
                        vatAmount = val
                        baseAmount = (val / (rate / 100.0) * 100).rounded() / 100
                    }
                }
                
                if let vat = vatAmount, let base = baseAmount {
                    let pctString = "\(Int(rate))%"
                    if !breakdowns.contains(where: { $0.percentage == pctString }) {
                        breakdowns.append(VatBreakdown(percentage: pctString, vatAmount: vat, baseAmount: base))
                    }
                }
            }
            
            if breakdowns.isEmpty {
                let totalVatPattern = "TOTAL\\s*TVA[^0-9]{0,15}?([0-9]+[,.][0-9]{2})"
                if let regex = try? NSRegularExpression(pattern: totalVatPattern, options: []),
                   let match = regex.firstMatch(in: fullText, options: [], range: NSRange(location: 0, length: fullText.utf16.count)), match.numberOfRanges > 1 {
                    let valString = (fullText as NSString).substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")
                    if let val = Double(valString) {
                        let pctString = "Mixt"
                        let base = result.totalAmount != nil ? (result.totalAmount! - val) : val
                        breakdowns.append(VatBreakdown(percentage: pctString, vatAmount: val, baseAmount: base))
                    }
                }
            }
            
            if !breakdowns.isEmpty {
                result.vatBreakdowns = breakdowns
                let sumVat = breakdowns.map { $0.vatAmount }.reduce(0, +)
                result.vatAmount = (sumVat * 100).rounded() / 100
                result.vatPercentages = breakdowns.map { $0.percentage }.joined(separator: ", ")
                result.vatRequiresVerification = false
                
                if result.totalAmount == nil {
                    let sumBase = breakdowns.map { $0.baseAmount }.reduce(0, +)
                    result.totalAmount = ((sumBase + result.vatAmount!) * 100).rounded() / 100
                    result.baseAmount = sumBase
                } else {
                    result.baseAmount = ((result.totalAmount! - result.vatAmount!) * 100).rounded() / 100
                }
            } else {
                result.vatAmount = 0
                result.vatPercentages = "-"
                result.baseAmount = result.totalAmount
            }
        }
    }
}

class FiscalComplianceAgent: AccountingAgent {
    var buyerCui: String?
    
    init(buyerCui: String?) {
        self.buyerCui = buyerCui
    }
    
    func process(textBlocks: [String], boxes: [OCRBoxItem], result: inout AccountingResult) async {
        let fullText = textBlocks.joined(separator: " ").uppercased()
        
        if result.documentType == "Bon Fiscal" {
            // Regula 1: Daca lipseste CUI cumparator de pe document
            if let bCui = buyerCui, !bCui.isEmpty {
                let normalizedFullText = fullText.replacingOccurrences(of: " ", with: "")
                let normalizedBuyerCui = bCui.uppercased().replacingOccurrences(of: " ", with: "")
                if !normalizedFullText.contains(normalizedBuyerCui) {
                    result.fiscalWarnings.append("Atenție: Bonul fiscal nu conține CUI-ul cumpărătorului (\(bCui)). TVA-ul este complet nedeductibil!")
                    result.documentTypeRequiresVerification = true
                }
            } else {
                result.fiscalWarnings.append("Sfat: Introduceți CUI-ul clientului pentru a verifica deductibilitatea bonului.")
            }
            
            // Regula 2: Verificare limita 100 EUR
            let eurRate = await fetchBnrEurRate()
            if let total = result.totalAmount {
                let limitRON = eurRate * 100.0
                if total > limitRON {
                    result.fiscalWarnings.append(String(format: "Atenție: Bonul fiscal depășește limita de ~100 EUR (%.2f RON) pentru a fi considerat factură simplificată.", limitRON))
                    result.totalRequiresVerification = true
                }
            }
        }
        
        if result.documentType == "Factură" {
            // Verificare numar si serie (reguli simple)
            let hasSeria = fullText.contains("SERIA") || fullText.contains("SERIE")
            let hasNumar = fullText.contains("NR.") || fullText.contains("NUMAR") || fullText.contains("NO.")
            
            if !hasSeria && !hasNumar {
                result.fiscalWarnings.append("Atenție: Documentul a fost clasificat ca Factură, dar nu conține elemente obligatorii clare (Seria / Numărul).")
                result.documentTypeRequiresVerification = true
            }
        }
    }
    
    private func fetchBnrEurRate() async -> Double {
        // Fallback rate in case of network failure
        let fallbackRate = 5.0
        guard let url = URL(string: "https://www.bnr.ro/nbrfxrates.xml") else { return fallbackRate }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let xmlString = String(data: data, encoding: .utf8) {
                // Simplest XML parsing via Regex to find <Rate currency="EUR">4.97</Rate>
                let pattern = "<Rate currency=\"EUR\">([0-9.]+)</Rate>"
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let nsString = xmlString as NSString
                    let results = regex.matches(in: xmlString, options: [], range: NSRange(location: 0, length: nsString.length))
                    if let match = results.first, match.numberOfRanges > 1 {
                        let matchedString = nsString.substring(with: match.range(at: 1))
                        if let rate = Double(matchedString) {
                            return rate
                        }
                    }
                }
            }
        } catch {
            return fallbackRate
        }
        return fallbackRate
    }
}

public class AccountingOrchestrator {
    public static let shared = AccountingOrchestrator()
    
    public func processOcrResult(boxes: [OCRBoxItem], buyerCui: String? = nil) async -> [AccountingResult] {
        // Generate textBlocks (grouped by lines) for legacy regex usage
        var textBlocks: [String] = []
        let sortedByY = boxes.sorted { $0.y < $1.y }
        if !sortedByY.isEmpty {
            var lines: [[OCRBoxItem]] = []
            var currentLine = [sortedByY[0]]
            let sortedHeights = sortedByY.map { $0.h }.sorted()
            let medianHeight = sortedHeights[sortedHeights.count / 2]
            let yTolerance = medianHeight * 0.4
            
            for box in sortedByY.dropFirst() {
                if abs(box.y - currentLine[0].y) < yTolerance {
                    currentLine.append(box)
                } else {
                    lines.append(currentLine)
                    currentLine = [box]
                }
            }
            lines.append(currentLine)
            
            textBlocks = lines.map { line -> String in
                let sortedLine = line.sorted { $0.x < $1.x }
                return sortedLine.map { $0.text }.joined(separator: " ")
            }
        }
        
        var result = AccountingResult()
        
        let agents: [AccountingAgent] = [
            DocumentClassificationAgent(),
            DocumentDetailsAgent(),
            CuiExtractorAgent(),
            FinancialAmountsAgent(),
            FiscalComplianceAgent(buyerCui: buyerCui)
        ]
        
        for agent in agents {
            await agent.process(textBlocks: textBlocks, boxes: boxes, result: &result)
        }
        
        // --- SPLIT LOGIC ---
        // Daca utilizatorul are mai multe cote TVA (sau doar una explicita din breakdown), 
        // dorim sa generam un rand separat pentru fiecare.
        if let breakdowns = result.vatBreakdowns, breakdowns.count > 0 {
            var splitResults: [AccountingResult] = []
            for b in breakdowns {
                var splitCopy = result
                splitCopy.vatPercentages = b.percentage
                splitCopy.vatAmount = b.vatAmount
                splitCopy.baseAmount = b.baseAmount
                // Setam totalul per rand ca suma dintre Baza aferenta si TVA-ul aferent.
                splitCopy.totalAmount = breakdowns.count > 1 ? ((b.baseAmount + b.vatAmount) * 100).rounded() / 100 : (result.totalAmount ?? ((b.baseAmount + b.vatAmount) * 100).rounded() / 100)
                // Curatam vectorul intern
                splitCopy.vatBreakdowns = nil
                splitResults.append(splitCopy)
            }
            return splitResults
        }
        
        return [result]
    }
    
    private func extractCUI(from text: String) -> String? {
        let clean = text.uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        
        let pattern = "[0-9]{2,10}"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsStr = clean as NSString
        let matches = regex.matches(in: clean, options: [], range: NSRange(location: 0, length: nsStr.length))
        
        for match in matches {
            let candidate = nsStr.substring(with: match.range)
            if isValidCUI(cui: candidate) {
                return candidate
            }
        }
        return nil
    }
    
    private func isBuyerCUIBox(_ box: OCRBoxItem, in boxes: [OCRBoxItem], medianHeight: CGFloat) -> Bool {
        let text = box.text.uppercased()
        let buyerKeywords = ["CLIENT", "CUMP", "BENEF", "CNP", "C.N.P"]
        
        for kw in buyerKeywords {
            if text.contains(kw) {
                return true
            }
        }
        
        for other in boxes {
            if other.x == box.x && other.y == box.y { continue }
            
            let otherText = other.text.uppercased()
            var hasBuyerKeyword = false
            for kw in buyerKeywords {
                if otherText.contains(kw) {
                    hasBuyerKeyword = true
                    break
                }
            }
            if !hasBuyerKeyword { continue }
            
            let dy = box.y - other.y
            let dx = box.x - other.x
            
            if abs(dy) < Double(medianHeight) * 1.5 && dx > 0 && dx < Double(medianHeight) * 12.0 {
                return true
            }
            
            if dy > 0 && dy < Double(medianHeight) * 2.5 && abs(dx) < Double(medianHeight) * 6.0 {
                return true
            }
        }
        
        return false
    }
    
    private func isSellerCUIBox(_ box: OCRBoxItem, in boxes: [OCRBoxItem], medianHeight: CGFloat) -> String? {
        guard let cui = extractCUI(from: box.text) else { return nil }
        
        if isBuyerCUIBox(box, in: boxes, medianHeight: medianHeight) {
            return nil
        }
        
        let text = box.text.uppercased()
        let sellerKeywords = ["CIF", "CUI", "CODFISCAL", "FISCAL", "C.I.F.", "C.F.", "RO"]
        
        var hasSellerKeyword = false
        for kw in sellerKeywords {
            if text.contains(kw) {
                hasSellerKeyword = true
                break
            }
        }
        
        if !hasSellerKeyword {
            for other in boxes {
                if other.x == box.x && other.y == box.y { continue }
                let otherText = other.text.uppercased()
                var otherHasKeyword = false
                for kw in sellerKeywords {
                    if otherText.contains(kw) {
                        otherHasKeyword = true
                        break
                    }
                }
                if !otherHasKeyword { continue }
                
                let dy = abs(box.y - other.y)
                let dx = abs(box.x - other.x)
                
                if dy < Double(medianHeight) * 2.0 && dx < Double(medianHeight) * 12.0 {
                    hasSellerKeyword = true
                    break
                }
            }
        }
        
        if hasSellerKeyword {
            return cui
        }
        
        return nil
    }

    // Separa cutiile de text in documente distincte
    func clusterBoxes(_ boxes: [OCRBoxItem]) -> [[OCRBoxItem]] {
        guard boxes.count > 1 else { return [boxes] }
        
        let sortedHeights = boxes.map { $0.h }.sorted()
        let medianHeight = CGFloat(sortedHeights[sortedHeights.count / 2])
        
        let debugLogUrl = URL(fileURLWithPath: "e:/OCR Iphone/OcrServer/debug_ocr.txt")
        func logToFile(_ text: String) {
            let line = text + "\n"
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: debugLogUrl.path) {
                    if let fileHandle = try? FileHandle(forWritingTo: debugLogUrl) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        fileHandle.closeFile()
                    }
                } else {
                    try? data.write(to: debugLogUrl)
                }
            }
        }
        
        logToFile("--- START CLUSTER BOXES ---")
        logToFile("Received \(boxes.count) boxes.")
        for b in boxes {
            logToFile("Box: '\(b.text)' at y=\(b.y), x=\(b.x)")
        }
        
        var uniqueAnchors: [OCRBoxItem] = []
        
        func isSellerAnchor(_ box: OCRBoxItem) -> Bool {
            let upper = box.text.uppercased()
            let noDots = upper.replacingOccurrences(of: ".", with: "")
            let noSpaces = noDots.replacingOccurrences(of: " ", with: "")
            
            let buyerKeywords = ["CLIENT", "CUMP", "BENEF", "CNP"]
            for kw in buyerKeywords {
                if noSpaces.contains(kw) { return false }
            }
            if upper.contains("%") { return false }
            if noSpaces.hasPrefix("BON") || noDots.contains("BON ") { return false }
            
            let sellerKeywords = ["CIF", "CODFISCAL", "IDENTIFICARE"]
            for kw in sellerKeywords {
                if noSpaces.contains(kw) { return true }
            }
            
            if noSpaces.hasPrefix("COD") && noSpaces.contains("FISCAL") { return true }
            return false
        }
        
        for box in boxes {
            if isSellerAnchor(box) {
                // Deduplicate anchors
                var isDuplicate = false
                for existing in uniqueAnchors {
                    let dx = abs(existing.x - box.x)
                    let dy = abs(existing.y - box.y)
                    if dx < medianHeight * 5.0 && dy < medianHeight * 3.0 {
                        isDuplicate = true
                        print("[CLUSTER] Duplicate anchor: '\(box.text)' at x=\(Int(box.x)) y=\(Int(box.y)) (prea aproape de o ancora existenta)")
                        break
                    }
                }
                
                if !isDuplicate {
                    uniqueAnchors.append(box)
                    let msg = "[CLUSTER] NEW anchor #\(uniqueAnchors.count): '\(box.text)' at x=\(Int(box.x)) y=\(Int(box.y))"
                    print(msg)
                    logToFile(msg)
                }
            }
        }
        
        let msgTotal = "[CLUSTER] medianHeight=\(medianHeight), total anchors=\(uniqueAnchors.count)"
        print(msgTotal)
        logToFile(msgTotal)
        
        var clusters: [[OCRBoxItem]] = []
        
        if uniqueAnchors.count > 1 {
            print("[CLUSTER] Using direct anchor assignment")
            logToFile("[CLUSTER] Using direct anchor assignment")
            
            var groups: [[OCRBoxItem]] = Array(repeating: [], count: uniqueAnchors.count)
            
            for box in boxes {
                var bestDist: Double = .infinity
                var bestIdx = 0
                
                for (i, anchor) in uniqueAnchors.enumerated() {
                    let dx = abs(box.x - anchor.x)
                    var dy = box.y - anchor.y
                    
                    // Box is physically above the anchor (by more than 2 lines) -> extremely unlikely to belong to this receipt
                    if dy < -Double(medianHeight) * 2.0 {
                        dy = abs(dy) + 10000.0
                    } else {
                        dy = abs(dy)
                    }
                    
                    // Horizontal distance is much worse than vertical distance (receipts are long vertically)
                    let dist = dx * 3.0 + dy
                    if dist < bestDist {
                        bestDist = dist
                        bestIdx = i
                    }
                }
                groups[bestIdx].append(box)
            }
            
            clusters = groups
            for (i, grp) in clusters.enumerated() {
                logToFile("Cluster \(i) received \(grp.count) boxes")
            }
        } else {
            clusters = recursiveXYCut(boxes, medianHeight: medianHeight)
        }
        
        clusters = clusters.filter { $0.count >= 3 }
        if clusters.isEmpty { return [boxes] }
        
        return clusters.sorted {
            if abs($0[0].y - $1[0].y) < Double(medianHeight) * 5.0 {
                return $0[0].x < $1[0].x
            }
            return $0[0].y < $1[0].y
        }
    }
    
    private func recursiveXYCut(_ boxes: [OCRBoxItem], medianHeight: CGFloat) -> [[OCRBoxItem]] {
        guard boxes.count > 1 else { return [boxes] }
        
        // 1. Tăietură pe X (cautam o coloana complet goala intre bonuri)
        let sortedX = boxes.sorted { $0.x < $1.x }
        var xIntervals: [(min: CGFloat, max: CGFloat)] = []
        
        for b in sortedX {
            if xIntervals.isEmpty {
                xIntervals.append((b.x, b.x + b.w))
            } else {
                let lastIdx = xIntervals.count - 1
                // Permitem o toleranță (daca un text centrat acopera gaura, intervalele se unesc)
                if b.x <= xIntervals[lastIdx].max + medianHeight * 2.5 {
                    xIntervals[lastIdx].max = max(xIntervals[lastIdx].max, b.x + b.w)
                } else {
                    xIntervals.append((b.x, b.x + b.w))
                }
            }
        }
        
        if xIntervals.count > 1 {
            var groups: [[OCRBoxItem]] = Array(repeating: [], count: xIntervals.count)
            for b in boxes {
                for (i, interval) in xIntervals.enumerated() {
                    if b.x >= interval.min - medianHeight && (b.x + b.w) <= interval.max + medianHeight {
                        groups[i].append(b)
                        break
                    }
                }
            }
            let validGroups = groups.filter { !$0.isEmpty }
            if validGroups.count > 1 {
                return validGroups.flatMap { recursiveXYCut($0, medianHeight: medianHeight) }
            }
        }
        
        // 2. Tăietură pe Y (cautam un rand complet gol intre bonuri, pe verticala)
        let sortedY = boxes.sorted { $0.y < $1.y }
        var yIntervals: [(min: CGFloat, max: CGFloat)] = []
        
        for b in sortedY {
            if yIntervals.isEmpty {
                yIntervals.append((b.y, b.y + b.h))
            } else {
                let lastIdx = yIntervals.count - 1
                if b.y <= yIntervals[lastIdx].max + medianHeight * 3.5 {
                    yIntervals[lastIdx].max = max(yIntervals[lastIdx].max, b.y + b.h)
                } else {
                    yIntervals.append((b.y, b.y + b.h))
                }
            }
        }
        
        if yIntervals.count > 1 {
            var groups: [[OCRBoxItem]] = Array(repeating: [], count: yIntervals.count)
            for b in boxes {
                for (i, interval) in yIntervals.enumerated() {
                    if b.y >= interval.min - medianHeight && (b.y + b.h) <= interval.max + medianHeight {
                        groups[i].append(b)
                        break
                    }
                }
            }
            let validGroups = groups.filter { !$0.isEmpty }
            if validGroups.count > 1 {
                return validGroups.flatMap { recursiveXYCut($0, medianHeight: medianHeight) }
            }
        }
        
        return [boxes]
    }
}

// MARK: - Fuzzy String Matching (Levenshtein)

extension String {
    func levenshteinDistance(to string: String) -> Int {
        let empty = [Int](repeating: 0, count: string.count + 1)
        var last = [Int](0...string.count)
        
        for (i, char1) in self.enumerated() {
            var cur = [i + 1] + empty.dropFirst()
            for (j, char2) in string.enumerated() {
                cur[j + 1] = char1 == char2 ? last[j] : Swift.min(last[j], last[j + 1], cur[j]) + 1
            }
            last = cur
        }
        return last.last ?? 0
    }
    
    func isFuzzyMatch(_ other: String, tolerance: Int = 1) -> Bool {
        return self.uppercased().levenshteinDistance(to: other.uppercased()) <= tolerance
    }
}

func isValidCUI(cui: String) -> Bool {
    guard cui.count >= 2 && cui.count <= 10 else { return false }
    guard let _ = Int(cui) else { return false }
    
    let controlKey = "753217532"
    let controlKeyReversed = String(controlKey.reversed())
    let cuiReversed = String(cui.reversed())
    
    var sum = 0
    let cuiArray = Array(cuiReversed)
    let keyArray = Array(controlKeyReversed)
    
    guard let controlDigit = Int(String(cuiArray[0])) else { return false }
    
    for i in 1..<cuiArray.count {
        if i - 1 < keyArray.count {
            if let cNum = Int(String(cuiArray[i])), let kNum = Int(String(keyArray[i - 1])) {
                sum += cNum * kNum
            }
        }
    }
    
    let calcControlDigit = (sum * 10) % 11
    let finalControlDigit = calcControlDigit == 10 ? 0 : calcControlDigit
    
    return finalControlDigit == controlDigit
}
