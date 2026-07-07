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
        // GET /debug_boxes - returneaza ultimele box-uri OCR procesate (pentru debug)
        app.get("debug_boxes") { req -> Response in
            let res = Response(status: .ok)
            res.headers.contentType = .json
            if let data = AccountingOrchestrator.shared.lastBoxesJson {
                res.body = .init(data: data)
            } else {
                res.body = .init(string: "{\"message\": \"No boxes processed yet. Upload an image first.\"}")
            }
            return res
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
    
    public var suggestedAccount: String?
    
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

        // 1. Cautare pe baza de Keywords
        let cuiKeywords = ["CIF", "CUI", "CODFISCAL", "RO", "R0", "IDENTIFICARE"]
        var candidateBoxes: [OCRBoxItem] = []
        
        for box in boxes {
            let cleanText = box.text.uppercased().replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
            if isBuyerBox(box) { continue }
            
            if cuiKeywords.contains(where: { cleanText.contains($0) || (cleanText.count <= $0.count + 2 && cleanText.isFuzzyMatch($0, tolerance: 1)) }) {
                candidateBoxes.append(box)
            }
        }
        
        // A. Cautam CUI-uri perfect valide (trec checksum-ul)
        // Verificam textul din interiorul cutiilor gasite
        for box in candidateBoxes {
            if box.text.contains("%") { continue }
            let text = box.text.uppercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ".", with: "")
            let numbersOnly = String(text.filter { $0.isNumber })
            if isValidCUI(cui: numbersOnly) {
                result.cui = numbersOnly
                result.cuiRequiresVerification = false
                await verifyWithANAF(cui: numbersOnly, result: &result)
                result.cui = numbersOnly 
                return
            }
        }
        
        // Cautam cutii vecine
        for keywordBox in candidateBoxes {
            let nearbyBoxes = boxes.filter {
                ($0.x != keywordBox.x || $0.y != keywordBox.y) &&
                $0.y >= keywordBox.y - keywordBox.h * 0.8 && $0.y <= keywordBox.y + keywordBox.h * 2.0 &&
                $0.x >= keywordBox.x - keywordBox.w * 0.5
            }.sorted { $0.x < $1.x }
            
            for nb in nearbyBoxes {
                if nb.text.contains("%") { continue }
                let text = nb.text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ".", with: "")
                let numbersOnly = String(text.filter { $0.isNumber })
                if isValidCUI(cui: numbersOnly) {
                    result.cui = numbersOnly
                    result.cuiRequiresVerification = false
                    await verifyWithANAF(cui: numbersOnly, result: &result)
                    result.cui = numbersOnly
                    return
                }
            }
        }
        
        // B. Fallback OCR (nu trec checksum-ul din cauza erorilor ex: "R0774547?" missing a zero)
        print("[CUI Extraction] No mathematically valid CUI found. Attempting OCR fallback for keyword candidates...")
        
        for box in candidateBoxes {
            if box.text.contains("%") { continue }
            let text = box.text.uppercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ".", with: "")
            let numbersOnly = String(text.filter { $0.isNumber })
            // Un CUI are intre 2 si 10 cifre. Daca avem 5+ cifre langa "CUI"/"RO", cel mai probabil e el.
            if numbersOnly.count >= 5 && numbersOnly.count <= 10 {
                result.cui = numbersOnly
                result.cuiRequiresVerification = true
                print("[CUI Extraction] Fallback matched invalid CUI string: '\(numbersOnly)'")
                return
            }
        }
        
        for keywordBox in candidateBoxes {
            let nearbyBoxes = boxes.filter {
                ($0.x != keywordBox.x || $0.y != keywordBox.y) &&
                $0.y >= keywordBox.y - keywordBox.h * 0.8 && $0.y <= keywordBox.y + keywordBox.h * 2.0 &&
                $0.x >= keywordBox.x - keywordBox.w * 0.5
            }.sorted { $0.x < $1.x }
            
            for nb in nearbyBoxes {
                if nb.text.contains("%") { continue }
                let text = nb.text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ".", with: "")
                let numbersOnly = String(text.filter { $0.isNumber })
                if numbersOnly.count >= 5 && numbersOnly.count <= 10 {
                    result.cui = numbersOnly
                    result.cuiRequiresVerification = true
                    print("[CUI Extraction] Fallback matched nearby invalid CUI string: '\(numbersOnly)'")
                    return
                }
            }
        }
        
        // Fara fallback global pe numere oarecare (ex: regex \b([0-9]{2,10})\b) deoarece atrage
        // "Totaluri" care trec de testul mod-11 accidental (ex: 146.26 -> 14626).
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
                // Check if this "TOTAL" is actually "TOTAL TVA" by checking nearby text
                let nearbyText = boxes.filter { b in
                    let dist = sqrt(pow(b.x - box.x, 2) + pow(b.y - box.y, 2))
                    return dist < medianHeight * 2.0 && !(b.x == box.x && b.y == box.y)
                }.map { $0.text.uppercased() }.joined(separator: " ") + " " + box.text.uppercased()
                
                var checkText = nearbyText
                checkText = checkText.replacingOccurrences(of: "TVA INCLUS", with: "")
                checkText = checkText.replacingOccurrences(of: "TVA INCL", with: "")
                checkText = checkText.replacingOccurrences(of: "TAXE INCLUSE", with: "")
                checkText = checkText.replacingOccurrences(of: "TAXA INCLUSA", with: "")
                if checkText.contains("TVA") || checkText.contains("TAXA") || checkText.contains("TAXE") {
                    continue
                }
                
                // Find the nearest box containing a decimal number
                // Sort all boxes by distance to this TOTAL box
                let candidates = boxes.filter { b in
                    !(b.x == box.x && b.y == box.y)
                }.sorted { b1, b2 in
                    let d1 = pow(b1.x - box.x, 2) + pow(b1.y - box.y, 2)
                    let d2 = pow(b2.x - box.x, 2) + pow(b2.y - box.y, 2)
                    return d1 < d2
                }
                
                for cand in candidates.prefix(8) {
                    let sanitized = cand.text.replacingOccurrences(of: ",", with: ".")
                    let pattern = "([0-9]+[.][0-9]{2})"
                    if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                       let match = regex.firstMatch(in: sanitized, options: [], range: NSRange(location: 0, length: sanitized.utf16.count)) {
                        let matchedString = (sanitized as NSString).substring(with: match.range(at: 1))
                        if let val = Double(matchedString), val > 1.0 {
                            // Sanity: skip if the number is likely a percentage (21.00, etc)
                            if val == 21.00 || val == 19.00 || val == 11.00 || val == 9.00 || val == 5.00 { continue }
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
                    if let val = Double(matchedString), val != 24.00, val != 21.00, val != 19.00, val != 11.00, val != 9.00, val != 5.00, val != 0.00 {
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
            
            // 1. GATHER ALL PERCENTAGES FROM THE DOCUMENT
            let pctPattern = "\\b([0-9]{1,2})(?:[.,][0-9]{1,2})?\\s*%"
            var rates: [Double] = []
            if let pctRegex = try? NSRegularExpression(pattern: pctPattern, options: []) {
                let matches = pctRegex.matches(in: fullText, options: [], range: NSRange(location: 0, length: fullText.utf16.count))
                for match in matches {
                    let pctStr = (fullText as NSString).substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")
                    if let rate = Double(pctStr), !rates.contains(rate) {
                        rates.append(rate)
                    }
                }
            }
            
            // 2. GATHER ALL DECIMAL AMOUNTS FROM THE DOCUMENT
            let decPattern = "(?<!%)\\b([0-9]+[.,][0-9]{2})\\b(?!\\s*%)"
            var allVals: [Double] = []
            if let decRegex = try? NSRegularExpression(pattern: decPattern, options: []) {
                let matches = decRegex.matches(in: fullText, options: [], range: NSRange(location: 0, length: fullText.utf16.count))
                for match in matches {
                    let valStr = (fullText as NSString).substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")
                    if let val = Double(valStr), !allVals.contains(val) {
                        allVals.append(val)
                    }
                }
            }
            
            // Daca nu am gasit nicio cota TVA explicita, folosim cotele din Romania (21, 19, 11, 9, 5) ca ipoteze
            if rates.isEmpty {
                rates = [21.0, 19.0, 11.0, 9.0, 5.0]
            }
            
            // 3. PURE MATHEMATICAL MATCHING (Rotation & Spatial Invariant)
            for rate in rates {
                if rate == 0.0 { continue }
                var vatAmount: Double? = nil
                var baseAmount: Double? = nil
                
                // Match Method A: Daca avem Totalul, testam daca vreun numar este TVA-ul (vat = total * rate / (100 + rate))
                if let total = result.totalAmount {
                    let expectedVat = (total * rate) / (100.0 + rate)
                    for val in allVals {
                        if abs(val - expectedVat) <= 0.05 {
                            vatAmount = val
                            baseAmount = ((total - val) * 100).rounded() / 100
                            break
                        }
                    }
                }
                
                // Match Method B: Cautam Baza si TVA direct in numerele extrase
                if vatAmount == nil {
                    for baseCand in allVals {
                        for vatCand in allVals {
                            if baseCand == vatCand { continue }
                            if abs(vatCand - baseCand * (rate / 100.0)) <= 0.05 {
                                vatAmount = vatCand
                                baseAmount = baseCand
                                break
                            }
                        }
                        if vatAmount != nil { break }
                    }
                }
                
                if let vat = vatAmount, let base = baseAmount {
                    let pctString = "\(Int(rate))%"
                    if !breakdowns.contains(where: { $0.percentage == pctString }) {
                        breakdowns.append(VatBreakdown(percentage: pctString, vatAmount: vat, baseAmount: base))
                    }
                }
            }
            
            // 4. FALLBACK: Cautare de proximitate daca nu trece matematic, dar gasim "TVA" scris langa un numar
            if breakdowns.isEmpty && fullText.contains("TVA") {
                if let total = result.totalAmount {
                    for box in boxes {
                        if box.text.uppercased().contains("TVA") {
                            let nearby = boxes.filter { $0.x != box.x || $0.y != box.y }
                                .sorted { (b1, b2) in
                                    let d1 = pow(b1.x - box.x, 2) + pow(b1.y - box.y, 2)
                                    let d2 = pow(b2.x - box.x, 2) + pow(b2.y - box.y, 2)
                                    return d1 < d2
                                }
                            if let closest = nearby.first,
                               let decRegex = try? NSRegularExpression(pattern: "(?<!%)\\b([0-9]+[.,][0-9]{2})\\b(?!\\s*%)", options: []),
                               let match = decRegex.firstMatch(in: closest.text, options: [], range: NSRange(location: 0, length: closest.text.utf16.count)) {
                                let valStr = (closest.text as NSString).substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")
                                if let val = Double(valStr), val > 0 && val < total * 0.3 {
                                    breakdowns.append(VatBreakdown(percentage: "Mixt", vatAmount: val, baseAmount: ((total - val) * 100).rounded() / 100))
                                    break
                                }
                            }
                        }
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

// MARK: - Agent Validare Contabila (Cunostinte Fiscale Romania 2026)

class AccountingValidationAgent: AccountingAgent {
    // Cote TVA legale Romania 2026
    static let validVatRates: [Double] = [0, 9, 11, 21]
    // Cota 9% e doar tranzitorie pentru locuinte noi, expira 31.07.2026
    
    func process(textBlocks: [String], boxes: [OCRBoxItem], result: inout AccountingResult) async {
        let fullText = textBlocks.joined(separator: " ").uppercased()
        
        // === 1. VALIDARE SI CORECTIE COTE TVA ===
        correctVatRates(result: &result, fullText: fullText)
        
        // === 2. VALIDARE MATEMATICA: Total = Baza + TVA ===
        validateMathematically(result: &result)
        
        // === 3. CATEGORIZARE CHELTUIELI (Cont Contabil Sugerat) ===
        suggestAccount(result: &result, fullText: fullText)
        
        // === 4. AVERTISMENTE SPECIFICE ===
        addSpecificWarnings(result: &result, fullText: fullText)
    }
    
    // Corectie automata cote TVA vechi -> cote 2026
    private func correctVatRates(result: inout AccountingResult, fullText: String) {
        guard let vatPct = result.vatPercentages else { return }
        
        // Detecteaza cota veche de 19% -> corectie la 21%
        if vatPct.contains("19%") {
            let oldVat = result.vatAmount ?? 0
            if let total = result.totalAmount, oldVat > 0 {
                // Recalculeaza cu 21%
                let newBase = (total / 1.21 * 100).rounded() / 100
                let newVat = ((total - newBase) * 100).rounded() / 100
                result.baseAmount = newBase
                result.vatAmount = newVat
                result.vatPercentages = "21%"
                result.fiscalWarnings.append("Corecție automată: Cota TVA 19% (veche) a fost recalculată la 21% (cota 2026). Verificați dacă bonul e din 2025+.")
            }
        }
        
        // Detecteaza cota veche de 5% -> corectie la 11%
        if vatPct.contains("5%") && !vatPct.contains("15%") && !vatPct.contains("25%") {
            if let total = result.totalAmount {
                let newBase = (total / 1.11 * 100).rounded() / 100
                let newVat = ((total - newBase) * 100).rounded() / 100
                result.baseAmount = newBase
                result.vatAmount = newVat
                result.vatPercentages = "11%"
                result.fiscalWarnings.append("Corecție automată: Cota TVA 5% (veche) a fost recalculată la 11% (cota 2026).")
            }
        }
        
        // Detecteaza cota de 9% pe NON-locuinte -> corectie la 11%
        // (9% e valid DOAR pentru locuinte noi pana la 31.07.2026)
        if vatPct == "9%" {
            let isHousing = fullText.contains("LOCUINT") || fullText.contains("APARTAMENT") || fullText.contains("IMOBIL")
            if !isHousing {
                if let total = result.totalAmount {
                    let newBase = (total / 1.11 * 100).rounded() / 100
                    let newVat = ((total - newBase) * 100).rounded() / 100
                    result.baseAmount = newBase
                    result.vatAmount = newVat
                    result.vatPercentages = "11%"
                    result.fiscalWarnings.append("Corecție automată: Cota TVA 9% este valabilă doar pentru locuințe noi (până la 31.07.2026). Recalculat la 11%.")
                }
            }
        }
    }
    
    // Validare: Total = Baza + TVA
    private func validateMathematically(result: inout AccountingResult) {
        guard let total = result.totalAmount,
              let vat = result.vatAmount,
              let base = result.baseAmount else { return }
        
        let expectedTotal = ((base + vat) * 100).rounded() / 100
        let diff = abs(total - expectedTotal)
        
        if diff > 0.02 && diff < total * 0.5 {
            // Diferenta mica -> probabil eroare OCR pe una din cifre
            // Recalculeaza baza din total - TVA (totalul e de obicei citit cel mai corect)
            let correctedBase = ((total - vat) * 100).rounded() / 100
            if correctedBase > 0 {
                result.baseAmount = correctedBase
                result.fiscalWarnings.append(String(format: "Corecție automată: Baza recalculată (%.2f) din Total (%.2f) - TVA (%.2f). Diferență detectată: %.2f RON.", correctedBase, total, vat, diff))
            }
        } else if diff >= total * 0.5 {
            // Diferenta foarte mare -> ceva e fundamental gresit
            result.fiscalWarnings.append(String(format: "⚠️ Eroare gravă: Total (%.2f) ≠ Bază (%.2f) + TVA (%.2f). Diferență: %.2f RON. Verificare manuală necesară!", total, base, vat, diff))
            result.totalRequiresVerification = true
        }
    }
    
    // Categorizare cheltuieli pe baza furnizorului/produselor
    private func suggestAccount(result: inout AccountingResult, fullText: String) {
        // Combustibil
        if fullText.contains("BENZINA") || fullText.contains("MOTORINA") || fullText.contains("DIESEL") ||
           fullText.contains("GPL") || fullText.contains("CARBURANT") || fullText.contains("MOL ") ||
           fullText.contains("PETROM") || fullText.contains("OMV") || fullText.contains("ROMPETROL") ||
           fullText.contains("LUKOIL") || fullText.contains("SOCAR") {
            result.suggestedAccount = "6022"
            return
        }
        
        // Utilități (gaz, electricitate, apă)
        if fullText.contains("GAZ ") || fullText.contains("GAZE") || fullText.contains("MAGISTRAL") ||
           fullText.contains("ELECTRICA") || fullText.contains("ENEL") || fullText.contains("E.ON") ||
           fullText.contains("APA ") || fullText.contains("HIDRO") {
            result.suggestedAccount = "605"
            return
        }
        
        // Telecomunicații
        if fullText.contains("VODAFONE") || fullText.contains("ORANGE") || fullText.contains("TELEKOM") ||
           fullText.contains("DIGI") || fullText.contains("RCS") || fullText.contains("RDS") {
            result.suggestedAccount = "626"
            return
        }
        
        // Restaurant / Alimentație
        if fullText.contains("RESTAURANT") || fullText.contains("PIZZ") || fullText.contains("FAST FOOD") ||
           fullText.contains("CAFEA") || fullText.contains("COFFEE") || fullText.contains("MENIU") {
            result.suggestedAccount = "625"
            return
        }
        
        // Hoteluri / Cazare
        if fullText.contains("HOTEL") || fullText.contains("CAZARE") || fullText.contains("PENSIUNE") ||
           fullText.contains("BOOKING") || fullText.contains("ACCOMMODATION") {
            result.suggestedAccount = "625"
            return
        }
        
        // Transport
        if fullText.contains("TAXI") || fullText.contains("UBER") || fullText.contains("BOLT") ||
           fullText.contains("CFR") || fullText.contains("BILET") || fullText.contains("TRANSPORT") ||
           fullText.contains("METROREX") || fullText.contains("STB") {
            result.suggestedAccount = "624"
            return
        }
        
        // Materiale consumabile / Papetărie
        if fullText.contains("PAPER") || fullText.contains("HARTIE") || fullText.contains("TONER") ||
           fullText.contains("CARTUS") || fullText.contains("PAPETARIE") || fullText.contains("BIROU") {
            result.suggestedAccount = "6028"
            return
        }
        
        // Magazine generale / Supermarket
        if fullText.contains("KAUFLAND") || fullText.contains("LIDL") || fullText.contains("MEGA IMAGE") ||
           fullText.contains("CARREFOUR") || fullText.contains("AUCHAN") || fullText.contains("PROFI") ||
           fullText.contains("PENNY") || fullText.contains("CORA") {
            result.suggestedAccount = "604"
            return
        }
        
        // Cosmetice / Parfumerie
        if fullText.contains("DOUGLAS") || fullText.contains("SEPHORA") || fullText.contains("COSMET") ||
           fullText.contains("PARFUM") {
            result.suggestedAccount = "604"
            return
        }
        
        // Farmacie / Medicamente
        if fullText.contains("FARMACI") || fullText.contains("CATENA") || fullText.contains("SENSIBLU") ||
           fullText.contains("HELPNET") || fullText.contains("DONA") || fullText.contains("MEDICAMENTE") {
            result.suggestedAccount = "604"
            return
        }
    }
    
    // Avertismente specifice per context
    private func addSpecificWarnings(result: inout AccountingResult, fullText: String) {
        // Restaurant cu posibilitate de factura mixta (11% mancare + 21% alcool)
        let isRestaurant = fullText.contains("RESTAURANT") || fullText.contains("PIZZ") || fullText.contains("FAST FOOD") || fullText.contains("CAFEA") || fullText.contains("MENIU")
        let hasAlcohol = fullText.contains("BERE") || fullText.contains("VIN ") || fullText.contains("WHISKY") || fullText.contains("VODKA") || fullText.contains("COCKTAIL") || fullText.contains("ALCOOL")
        
        if isRestaurant && hasAlcohol {
            result.fiscalWarnings.append("Atenție: Factura de restaurant conține și băuturi alcoolice. TVA-ul poate fi mixt: 11% pentru mâncare, 21% pentru alcool.")
        }
        
        // Bon fiscal fara CUI cumparator -> TVA nedeductibil
        if result.documentType == "Bon Fiscal" && (result.cui == nil || result.cui?.isEmpty == true) {
            // Deja tratat in FiscalComplianceAgent, dar adaugam si sugestie
        }
        
        // Verificare data bon — daca e din 2024 sau inainte, cotele vechi erau corecte
        if let dateStr = result.documentDate {
            let yearPattern = "20(2[0-4])"
            if let regex = try? NSRegularExpression(pattern: yearPattern, options: []),
               regex.firstMatch(in: dateStr, options: [], range: NSRange(location: 0, length: dateStr.utf16.count)) != nil {
                // Bonul e din 2024 sau mai devreme -> cotele vechi (19%, 9%, 5%) erau corecte
                // Stergem warning-urile de corectie automata daca exista
                result.fiscalWarnings = result.fiscalWarnings.filter { !$0.contains("Corecție automată: Cota TVA") }
            }
        }
    }
}

public class AccountingOrchestrator {
    public static let shared = AccountingOrchestrator()
    
    // Stocam ultimele box-uri procesate pentru endpoint-ul /debug_boxes
    public var lastBoxesJson: Data?
    
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
            FiscalComplianceAgent(buyerCui: buyerCui),
            AccountingValidationAgent()
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
    // STRATEGIA CASCADA (robust pentru orice tip de imagine/PDF):
    //   Nivel 1: CUI anchors (COD FISCAL / Cod Identificare Fiscala / CIF standalone)
    //   Nivel 2: BON FISCAL anchors (fallback daca OCR nu detecteaza CUI)
    //   Nivel 3: Union-Find spatial proximity (fallback final pentru imagini fara text fiscal)
    // Dupa fiecare nivel: Pass 2 split daca un cluster contine mai multe CUI-uri
    func clusterBoxes(_ boxes: [OCRBoxItem]) -> [[OCRBoxItem]] {
        guard boxes.count > 1 else { return [boxes] }
        
        let sortedHeights = boxes.map { $0.h }.sorted()
        let medianHeight = Double(sortedHeights[sortedHeights.count / 2])
        
        // === STOCARE PENTRU /debug_boxes ===
        do {
            struct BoxDump: Codable {
                let text: String; let x: Double; let y: Double; let w: Double; let h: Double
            }
            let dumpBoxes = boxes.map { BoxDump(text: $0.text, x: $0.x, y: $0.y, w: $0.w, h: $0.h) }
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(dumpBoxes)
            AccountingOrchestrator.shared.lastBoxesJson = jsonData
        } catch {}
        
        print("[CLUSTER] === START === boxes=\(boxes.count), medianHeight=\(medianHeight)")
        
        // =====================================================================
        // HELPER FUNCTIONS
        // =====================================================================
        
        func isBuyerText(_ text: String) -> Bool {
            let t = text.uppercased()
            return t.contains("CLIENT") || t.contains("CUMP") || t.contains("BENEF") || t.contains("CNP")
        }
        
        // Sortare finala: pe Y apoi pe X
        func sortClusters(_ clusters: inout [[OCRBoxItem]]) {
            clusters.sort {
                let y0 = $0.map { $0.y }.min() ?? 0
                let y1 = $1.map { $0.y }.min() ?? 0
                let x0 = $0.map { $0.x }.min() ?? 0
                let x1 = $1.map { $0.x }.min() ?? 0
                if abs(y0 - y1) < medianHeight * 5.0 { return x0 < x1 }
                return y0 < y1
            }
        }
        
        // =====================================================================
        // FIND CUI ANCHORS
        // =====================================================================
        
        var cuiAnchors: [OCRBoxItem] = []
        
        for box in boxes {
            if isBuyerText(box.text) { continue }
            let upper = box.text.uppercased()
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: ".", with: "")
            if upper.contains("CODFISCAL") || upper.contains("CODIDENTIFICARE") || upper.contains("IDENTIFICAREFISCALA") {
                let numbersOnly = box.text.filter { $0.isNumber }
                if numbersOnly.count >= 5 {
                    var dup = false
                    for e in cuiAnchors {
                        if abs(e.x - box.x) < medianHeight * 3 && abs(e.y - box.y) < medianHeight * 2 {
                            dup = true; break
                        }
                    }
                    if !dup {
                        cuiAnchors.append(box)
                        print("[CLUSTER] CUI anchor: '\(box.text)' x=\(Int(box.x)) y=\(Int(box.y))")
                    }
                }
            }
        }
        
        // "CIF" standalone
        for box in boxes {
            if isBuyerText(box.text) { continue }
            let trimmed = box.text.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ".", with: "")
            if trimmed == "CIF" || trimmed == "C I F" || trimmed == "CIF:" {
                for box2 in boxes {
                    if abs(box2.x - box.x) < medianHeight * 2 {
                        let hasLongNumber = box2.text.replacingOccurrences(of: " ", with: "")
                            .filter { $0.isNumber }.count >= 7
                        if hasLongNumber {
                            var dup = false
                            for e in cuiAnchors {
                                if abs(e.x - box.x) < medianHeight * 3 && abs(e.y - box.y) < medianHeight * 2 {
                                    dup = true; break
                                }
                            }
                            if !dup {
                                cuiAnchors.append(box)
                                print("[CLUSTER] CIF standalone: '\(box.text)' x=\(Int(box.x)) y=\(Int(box.y))")
                            }
                            break
                        }
                    }
                }
            }
        }
        
        print("[CLUSTER] Found \(cuiAnchors.count) CUI anchors")
        
        // =====================================================================
        // RECURSIVE BISECTION CLUSTERING
        // Splits box groups along the axis where CUI anchors have the largest
        // gap, using actual box position gaps rather than midpoints.
        // Works universally: rotated, 2D grids, single columns, any layout.
        // =====================================================================
        
        if cuiAnchors.count > 1 {
            
            func getAnchorsIn(_ group: [OCRBoxItem]) -> [OCRBoxItem] {
                return cuiAnchors.filter { anchor in
                    group.contains { $0.x == anchor.x && $0.y == anchor.y && $0.text == anchor.text }
                }
            }
            
            func findBestGapSplit(_ group: [OCRBoxItem], axis: String) -> Double? {
                let anchorsInGroup = getAnchorsIn(group)
                if anchorsInGroup.count < 2 { return nil }
                
                let centers: [Double]
                let anchorPositions: [Double]
                
                if axis == "x" {
                    centers = group.map { $0.x + $0.w / 2.0 }.sorted()
                    anchorPositions = anchorsInGroup.map { $0.x + $0.w / 2.0 }
                } else {
                    centers = group.map { $0.y + $0.h / 2.0 }.sorted()
                    anchorPositions = anchorsInGroup.map { $0.y + $0.h / 2.0 }
                }
                
                var bestGap: Double = 0
                var bestSplit: Double? = nil
                
                for i in 1..<centers.count {
                    let gap = centers[i] - centers[i - 1]
                    if gap <= bestGap { continue }
                    
                    let splitPoint = (centers[i - 1] + centers[i]) / 2.0
                    
                    let leftAnchors = anchorPositions.filter { $0 < splitPoint }.count
                    let rightAnchors = anchorPositions.filter { $0 >= splitPoint }.count
                    
                    if leftAnchors > 0 && rightAnchors > 0 {
                        bestGap = gap
                        bestSplit = splitPoint
                    }
                }
                
                return bestSplit
            }
            
            func recursiveSplit(_ group: [OCRBoxItem], depth: Int = 0) -> [[OCRBoxItem]] {
                let anchorsInGroup = getAnchorsIn(group)
                
                if anchorsInGroup.count <= 1 {
                    return [group]
                }
                
                let splitX = findBestGapSplit(group, axis: "x")
                let splitY = findBestGapSplit(group, axis: "y")
                
                func gapSize(_ group: [OCRBoxItem], _ axis: String, _ splitPoint: Double?) -> Double {
                    guard let sp = splitPoint else { return 0 }
                    let centers: [Double]
                    if axis == "x" {
                        centers = group.map { $0.x + $0.w / 2.0 }.sorted()
                    } else {
                        centers = group.map { $0.y + $0.h / 2.0 }.sorted()
                    }
                    let leftMax = centers.filter { $0 < sp }.max() ?? sp
                    let rightMin = centers.filter { $0 >= sp }.min() ?? sp
                    return rightMin - leftMax
                }
                
                var gapX = gapSize(group, "x", splitX)
                var gapY = gapSize(group, "y", splitY)
                
                var finalSplitX = splitX
                var finalSplitY = splitY
                
                // Fallback: midpoint between most distant anchors
                if gapX == 0 && gapY == 0 {
                    let anchorXs = anchorsInGroup.map { $0.x + $0.w / 2.0 }.sorted()
                    let anchorYs = anchorsInGroup.map { $0.y + $0.h / 2.0 }.sorted()
                    let xSpread = (anchorXs.last ?? 0) - (anchorXs.first ?? 0)
                    let ySpread = (anchorYs.last ?? 0) - (anchorYs.first ?? 0)
                    
                    if xSpread >= ySpread {
                        var bestG = 0.0
                        for i in 1..<anchorXs.count {
                            let g = anchorXs[i] - anchorXs[i - 1]
                            if g > bestG { bestG = g; finalSplitX = (anchorXs[i - 1] + anchorXs[i]) / 2.0 }
                        }
                        gapX = bestG
                    } else {
                        var bestG = 0.0
                        for i in 1..<anchorYs.count {
                            let g = anchorYs[i] - anchorYs[i - 1]
                            if g > bestG { bestG = g; finalSplitY = (anchorYs[i - 1] + anchorYs[i]) / 2.0 }
                        }
                        gapY = bestG
                    }
                }
                
                let left: [OCRBoxItem]
                let right: [OCRBoxItem]
                
                if gapX >= gapY, let sp = finalSplitX {
                    print("[CLUSTER] Depth \(depth): Split on X at \(Int(sp)) (gap=\(Int(gapX)))")
                    left = group.filter { $0.x + $0.w / 2.0 < sp }
                    right = group.filter { $0.x + $0.w / 2.0 >= sp }
                } else if let sp = finalSplitY {
                    print("[CLUSTER] Depth \(depth): Split on Y at \(Int(sp)) (gap=\(Int(gapY)))")
                    left = group.filter { $0.y + $0.h / 2.0 < sp }
                    right = group.filter { $0.y + $0.h / 2.0 >= sp }
                } else {
                    return [group]
                }
                
                var result: [[OCRBoxItem]] = []
                if !left.isEmpty { result.append(contentsOf: recursiveSplit(left, depth: depth + 1)) }
                if !right.isEmpty { result.append(contentsOf: recursiveSplit(right, depth: depth + 1)) }
                return result
            }
            
            var clusters = recursiveSplit(boxes)
            clusters = clusters.filter { $0.count >= 3 }
            
            if clusters.count > 1 {
                sortClusters(&clusters)
                print("[CLUSTER] === DONE (Recursive Bisection) === Returning \(clusters.count) clusters")
                for (i, c) in clusters.enumerated() {
                    let minY = c.map { $0.y }.min() ?? 0
                    let minX = c.map { $0.x }.min() ?? 0
                    print("[CLUSTER]   Cluster \(i): \(c.count) boxes, topLeft=(\(Int(minX)),\(Int(minY)))")
                }
                return clusters
            }
        }
        
        // Single receipt or no CUI anchors - return all as one cluster
        print("[CLUSTER] === DONE === No splitting needed, returning all as 1 cluster")
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
