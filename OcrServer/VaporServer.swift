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
        // Find Company Name
        var companyName: String? = nil
        for box in boxes {
            let t = box.text.uppercased()
            if t.contains("SRL") || t.contains("S.R.L") || t.contains("SA") || t.contains("S.A.") || t.contains("SNC") {
                companyName = box.text
                break
            }
        }
        if companyName == nil, let firstBox = boxes.first(where: { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).count > 3 }) {
            companyName = firstBox.text
        }
        result.companyName = companyName
        
        let fullText = boxes.map { $0.text }.joined(separator: " \n ").uppercased()
        
        let seriesPattern = "(?:SERIA|SERIE|SERIA:|CHITANTA\\s*SERIA)\\s*([A-Z]{1,5})"
        if let regex = try? NSRegularExpression(pattern: seriesPattern, options: []) {
            let nsString = fullText as NSString
            let match = regex.firstMatch(in: fullText, options: [], range: NSRange(location: 0, length: nsString.length))
            if let m = match, m.numberOfRanges > 1 {
                result.documentSeries = nsString.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        let numberPattern = "(?:NR\\.?|NUMAR|BON\\s*NR\\.?|FACTURA\\s*NR\\.?|CHITANTA\\s*NR\\.?|BF\\.?|ID\\s*TRX\\.?)\\s*[:]*\\s*([0-9]{1,15})"
        if let regex = try? NSRegularExpression(pattern: numberPattern, options: []) {
            let nsString = fullText as NSString
            let match = regex.firstMatch(in: fullText, options: [], range: NSRange(location: 0, length: nsString.length))
            if let m = match, m.numberOfRanges > 1 {
                result.documentNumber = nsString.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        let datePattern = "(?:DATA\\s*[:]*\\s*)?([0-3]?[0-9][\\.\\-\\/][0-1]?[0-9][\\.\\-\\/](?:20)?[0-9]{2})"
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
    
    private func verifyWithANAF(cui: String, result: inout AccountingResult) async {
        let urlString = "https://webservicesp.anaf.ro/PlatitorTvaRest/api/v8/ws/tva"
        guard let url = URL(string: urlString) else {
            result.cuiRequiresVerification = true
            return
        }
        
        let currentDate = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: currentDate)
        
        let payload: [[String: String]] = [
            ["cui": cui, "data": dateString]
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
            result.cuiRequiresVerification = true
        }
    }

    func cleanFallbackCandidate(_ rawText: String) -> String? {
        let upper = rawText.uppercased()
        var s = ""
        for char in upper {
            if char.isLetter || char.isNumber {
                s.append(char)
            }
        }
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

    func process(textBlocks: [String], boxes: [OCRBoxItem], result: inout AccountingResult) async {
        let sortedHeights = boxes.map { $0.h }.sorted()
        let medianHeight = sortedHeights.isEmpty ? 15.0 : CGFloat(sortedHeights[sortedHeights.count / 2])

        func isBuyerCUIBoxLocal(_ box: OCRBoxItem) -> Bool {
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
                
                // Scenario 1: Same line, label to the left
                if abs(dy) < Double(medianHeight) * 1.5 && dx > 0 && dx < Double(medianHeight) * 12.0 {
                    return true
                }
                
                // Scenario 2: Label is directly above
                if dy > 0 && dy < Double(medianHeight) * 2.5 && abs(dx) < Double(medianHeight) * 6.0 {
                    return true
                }
            }
            
            return false
        }

        func isPhoneOrPhoneLabelLocal(_ box: OCRBoxItem) -> Bool {
            let text = box.text.uppercased()
            let phoneLabels = ["TEL", "FAX", "MOBIL", "TELEFON"]
            for label in phoneLabels {
                if text.contains(label) {
                    return true
                }
            }
            
            let digits = text.filter { $0.isNumber }
            if digits.count == 10 && (digits.hasPrefix("07") || digits.hasPrefix("02") || digits.hasPrefix("03")) {
                return true
            }
            
            for other in boxes {
                let otherText = other.text.uppercased()
                var hasPhoneLabel = false
                for label in phoneLabels {
                    if otherText.contains(label) {
                        hasPhoneLabel = true
                        break
                    }
                }
                if !hasPhoneLabel { continue }
                
                let dy = abs(box.y - other.y)
                let dx = abs(box.x - other.x)
                if dy < Double(medianHeight) * 1.5 && dx < Double(medianHeight) * 12.0 {
                    return true
                }
            }
            
            return false
        }

        let cuiKeywords = ["CIF", "CUI", "CODFISCAL", "R0", "IDENTIFICARE"]
        var candidateBoxes: [OCRBoxItem] = []
        
        for box in boxes {
            if isBuyerCUIBoxLocal(box) { continue }
            if isPhoneOrPhoneLabelLocal(box) { continue }
            let cleanText = box.text.uppercased().replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
            
            var isCandidate = cuiKeywords.contains(where: { cleanText.contains($0) || (cleanText.count <= $0.count + 2 && cleanText.isFuzzyMatch($0, tolerance: 1)) })
            if !isCandidate {
                isCandidate = containsRefinedRo(box.text)
            }
            
            if isCandidate {
                candidateBoxes.append(box)
            }
        }
        
        for box in candidateBoxes {
            if box.text.contains("%") { continue }
            if isBuyerCUIBoxLocal(box) { continue }
            if isPhoneOrPhoneLabelLocal(box) { continue }
            if let cui = extractCUI(from: box.text) {
                result.cui = cui
                result.cuiRequiresVerification = false
                await verifyWithANAF(cui: cui, result: &result)
                result.cui = cui 
                return
            }
        }
        
        for keywordBox in candidateBoxes {
            let nearbyBoxes = boxes.filter {
                let dist = sqrt(pow($0.x - keywordBox.x, 2) + pow($0.y - keywordBox.y, 2))
                return dist < medianHeight * 3.0 && !($0.x == keywordBox.x && $0.y == keywordBox.y)
            }.sorted { b1, b2 in
                let d1 = pow(b1.x - keywordBox.x, 2) + pow(b1.y - keywordBox.y, 2)
                let d2 = pow(b2.x - keywordBox.x, 2) + pow(b2.y - keywordBox.y, 2)
                return d1 < d2
            }
            
            for nb in nearbyBoxes {
                if nb.text.contains("%") { continue }
                if isBuyerCUIBoxLocal(nb) { continue }
                if isPhoneOrPhoneLabelLocal(nb) { continue }
                if let cui = extractCUI(from: nb.text) {
                    result.cui = cui
                    result.cuiRequiresVerification = false
                    await verifyWithANAF(cui: cui, result: &result)
                    result.cui = cui
                    return
                }
            }
        }
        
        for box in boxes {
            if box.text.contains("%") { continue }
            if isBuyerCUIBoxLocal(box) { continue }
            if isPhoneOrPhoneLabelLocal(box) { continue }
            if let cui = extractCUI(from: box.text) {
                result.cui = cui
                result.cuiRequiresVerification = false
                await verifyWithANAF(cui: cui, result: &result)
                result.cui = cui
                return
            }
        }
        
        // Typo Fallback: extract alphanumeric sequences (length 2-12) from nearby boxes
        var fallbackCandidates: [(text: String, dist: Double)] = []
        for box in candidateBoxes {
            if isBuyerCUIBoxLocal(box) { continue }
            if isPhoneOrPhoneLabelLocal(box) { continue }
            if let cleaned = cleanFallbackCandidate(box.text) {
                fallbackCandidates.append((text: cleaned, dist: 0.0))
            }
        }
        for keywordBox in candidateBoxes {
            let nearby = boxes.filter {
                let dist = sqrt(pow($0.x - keywordBox.x, 2) + pow($0.y - keywordBox.y, 2))
                return dist < medianHeight * 5.0 && !($0.x == keywordBox.x && $0.y == keywordBox.y)
            }
            for nb in nearby {
                if nb.text.contains("%") { continue }
                if isBuyerCUIBoxLocal(nb) { continue }
                if isPhoneOrPhoneLabelLocal(nb) { continue }
                if let cleaned = cleanFallbackCandidate(nb.text) {
                    let dist = sqrt(pow(nb.x - keywordBox.x, 2) + pow(nb.y - keywordBox.y, 2))
                    fallbackCandidates.append((text: cleaned, dist: dist))
                }
            }
        }
        if !fallbackCandidates.isEmpty {
            fallbackCandidates.sort { $0.dist < $1.dist }
            let best = fallbackCandidates[0].text
            result.cui = best
            result.cuiRequiresVerification = true
            await verifyWithANAF(cui: best, result: &result)
            result.cui = best
            return
        }
        
        result.cuiRequiresVerification = true
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
                let avgY = currentLine.reduce(0.0) { $0 + $1.y } / Double(currentLine.count)
                if abs(box.y - avgY) < yTolerance {
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
                    let pattern = "([0-9]{1,3}(?:[.,\\s][0-9]{3})+(?:[.,][0-9]{1,2})?|[0-9]+(?:[.,][0-9]{1,2})?)"
                    if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                       let match = regex.firstMatch(in: cand.text, options: [], range: NSRange(location: 0, length: cand.text.utf16.count)) {
                        let matchedString = (cand.text as NSString).substring(with: match.range(at: 1))
                        if let val = parseFormattedAmount(matchedString), val > 1.0 {
                            // Sanity: skip if the number is likely a percentage (21.00, etc)
                            if val == 21.0 || val == 19.0 || val == 11.0 || val == 9.0 || val == 5.0 { continue }
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
            let totalPattern = "(?i)(?:TOTAL|SUMA|ACHITAT)[ \\t]*(?:LEI)?[ \\t]*[:=]*[ \\t]*([0-9]{1,3}(?:[.,\\s][0-9]{3})+(?:[.,][0-9]{1,2})?|[0-9]+(?:[.,][0-9]{1,2})?)"
            if let regex = try? NSRegularExpression(pattern: totalPattern, options: []),
               let match = regex.firstMatch(in: fullText, options: [], range: NSRange(location: 0, length: fullText.utf16.count)) {
                let matchedString = (fullText as NSString).substring(with: match.range(at: 1))
                if let val = parseFormattedAmount(matchedString) {
                    result.totalAmount = val
                    result.totalRequiresVerification = false
                    totalFound = true
                }
            }
        }
        
        // Final Fallback: largest number
        if result.totalAmount == nil {
            let pattern = "(?<!%)\\b([0-9]{1,3}(?:[.,\\s][0-9]{3})+(?:[.,][0-9]{1,2})?|[0-9]+(?:[.,][0-9]{1,2})?)\\b(?!\\s*%)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsString = fullText as NSString
                let results = regex.matches(in: fullText, options: [], range: NSRange(location: 0, length: nsString.length))
                var amounts: [Double] = []
                for match in results {
                    let matchedString = nsString.substring(with: match.range(at: 1))
                    if let val = parseFormattedAmount(matchedString), val != 24.0, val != 21.0, val != 19.0, val != 11.0, val != 9.0, val != 5.0, val != 0.0 {
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
            let decPattern = "(?<!%)\\b([0-9]{1,3}(?:[.,\\s][0-9]{3})+(?:[.,][0-9]{1,2})?|[0-9]+(?:[.,][0-9]{1,2})?)\\b(?!\\s*%)"
            var allVals: [Double] = []
            if let decRegex = try? NSRegularExpression(pattern: decPattern, options: []) {
                let matches = decRegex.matches(in: fullText, options: [], range: NSRange(location: 0, length: fullText.utf16.count))
                for match in matches {
                    let valStr = (fullText as NSString).substring(with: match.range(at: 1))
                    if let val = parseFormattedAmount(valStr), !allVals.contains(val) {
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
                            for closest in nearby.prefix(10) {
                                let sanitized = closest.text.replacingOccurrences(of: " ", with: "")
                                if let decRegex = try? NSRegularExpression(pattern: "([0-9]{1,3}(?:[.,\\s][0-9]{3})+(?:[.,][0-9]{1,2})?|[0-9]+(?:[.,][0-9]{1,2})?)", options: []),
                                   let match = decRegex.firstMatch(in: sanitized, options: [], range: NSRange(location: 0, length: sanitized.utf16.count)) {
                                    let valStr = (sanitized as NSString).substring(with: match.range(at: 1))
                                    if let val = parseFormattedAmount(valStr), val > 0 && val < total * 0.3 {
                                        breakdowns.append(VatBreakdown(percentage: "Mixt", vatAmount: val, baseAmount: ((total - val) * 100).rounded() / 100))
                                        break
                                    }
                                }
                            }
                            if !breakdowns.isEmpty { break }
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
    
    private func getYearFromDate(_ dateStr: String) -> Int? {
        let components = dateStr.components(separatedBy: CharacterSet(charactersIn: ".-/"))
        if let last = components.last?.trimmingCharacters(in: .whitespacesAndNewlines),
           let year = Int(last) {
            if last.count == 2 {
                if year <= 50 {
                    return 2000 + year
                } else {
                    return 1900 + year
                }
            } else if last.count == 4 {
                return year
            }
        }
        return nil
    }

    // Corectie automata cote TVA vechi -> cote 2026
    private func correctVatRates(result: inout AccountingResult, fullText: String) {
        if let dateStr = result.documentDate {
            if let year = getYearFromDate(dateStr), year <= 2024 {
                return
            }
        }
        
        guard let vatPct = result.vatPercentages else { return }
        
        if var breakdowns = result.vatBreakdowns, !breakdowns.isEmpty {
            var updatedBreakdowns: [VatBreakdown] = []
            var updatedPercentages: [String] = []
            var correctedAny = false
            
            for b in breakdowns {
                var newPct = b.percentage
                var newBase = b.baseAmount
                var newVat = b.vatAmount
                
                if b.percentage == "19%" {
                    newPct = "21%"
                    let total = b.baseAmount + b.vatAmount
                    newBase = (total / 1.21 * 100).rounded() / 100
                    newVat = ((total - newBase) * 100).rounded() / 100
                    correctedAny = true
                    result.fiscalWarnings.append("Corecție automată: Cota TVA 19% (veche) a fost recalculată la 21% (cota 2026). Verificați dacă bonul e din 2025+.")
                } else if b.percentage == "5%" {
                    newPct = "11%"
                    let total = b.baseAmount + b.vatAmount
                    newBase = (total / 1.11 * 100).rounded() / 100
                    newVat = ((total - newBase) * 100).rounded() / 100
                    correctedAny = true
                    result.fiscalWarnings.append("Corecție automată: Cota TVA 5% (veche) a fost recalculată la 11% (cota 2026).")
                } else if b.percentage == "9%" {
                    let isHousing = fullText.contains("LOCUINT") || fullText.contains("APARTAMENT") || fullText.contains("IMOBIL")
                    if !isHousing {
                        newPct = "11%"
                        let total = b.baseAmount + b.vatAmount
                        newBase = (total / 1.11 * 100).rounded() / 100
                        newVat = ((total - newBase) * 100).rounded() / 100
                        correctedAny = true
                        result.fiscalWarnings.append("Corecție automată: Cota TVA 9% este valabilă doar pentru locuințe noi (până la 31.07.2026). Recalculat la 11%.")
                    }
                }
                
                updatedBreakdowns.append(VatBreakdown(percentage: newPct, vatAmount: newVat, baseAmount: newBase))
                updatedPercentages.append(newPct)
            }
            
            if correctedAny {
                result.vatBreakdowns = updatedBreakdowns
                let totalBase = updatedBreakdowns.reduce(0.0) { $0 + $1.baseAmount }
                let totalVat = updatedBreakdowns.reduce(0.0) { $0 + $1.vatAmount }
                result.baseAmount = totalBase
                result.vatAmount = totalVat
                var uniquePercentages: [String] = []
                for p in updatedPercentages {
                    if !uniquePercentages.contains(p) {
                        uniquePercentages.append(p)
                    }
                }
                result.vatPercentages = uniquePercentages.joined(separator: ", ")
            }
        } else {
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
            if let year = getYearFromDate(dateStr), year <= 2024 {
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
                let avgY = currentLine.reduce(0.0) { $0 + $1.y } / Double(currentLine.count)
                if abs(box.y - avgY) < yTolerance {
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
    
    func isBuyerCUIBox(_ box: OCRBoxItem, in boxes: [OCRBoxItem], medianHeight: CGFloat) -> Bool {
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
        
        // === 1. Skew Angle & Deskewing ===
        var angles: [Double] = []
        for box in boxes {
            if let rect = box.rect {
                let theta_i = atan2(rect.topRight_y - rect.topLeft_y, rect.topRight_x - rect.topLeft_x)
                angles.append(theta_i)
            } else {
                angles.append(0.0)
            }
        }
        let sortedAngles = angles.sorted()
        let theta = sortedAngles.isEmpty ? 0.0 : sortedAngles[sortedAngles.count / 2]
        
        let cosT = cos(-theta)
        let sinT = sin(-theta)
        let deskewedBoxes = boxes.map { box -> OCRBoxItem in
            let cx = box.x + box.w / 2.0
            let cy = box.y + box.h / 2.0
            let cxPrime = cx * cosT - cy * sinT
            let cyPrime = cx * sinT + cy * cosT
            let newX = cxPrime - box.w / 2.0
            let newY = cyPrime - box.h / 2.0
            
            var newRect: OCRRectItem? = nil
            if let r = box.rect {
                newRect = OCRRectItem(
                    topLeft_x: r.topLeft_x * cosT - r.topLeft_y * sinT,
                    topLeft_y: r.topLeft_x * sinT + r.topLeft_y * cosT,
                    topRight_x: r.topRight_x * cosT - r.topRight_y * sinT,
                    topRight_y: r.topRight_x * sinT + r.topRight_y * cosT,
                    bottomLeft_x: r.bottomLeft_x * cosT - r.bottomLeft_y * sinT,
                    bottomLeft_y: r.bottomLeft_x * sinT + r.bottomLeft_y * cosT,
                    bottomRight_x: r.bottomRight_x * cosT - r.bottomRight_y * sinT,
                    bottomRight_y: r.bottomRight_x * sinT + r.bottomRight_y * cosT
                )
            }
            return OCRBoxItem(text: box.text, x: newX, y: newY, w: box.w, h: box.h, rect: newRect)
        }
        
        let sortedHeights = deskewedBoxes.map { $0.h }.sorted()
        let medianHeight = Double(sortedHeights[sortedHeights.count / 2])
        
        // === STOCARE PENTRU /debug_boxes ===
        do {
            struct BoxDump: Codable {
                let text: String; let x: Double; let y: Double; let w: Double; let h: Double
            }
            let dumpBoxes = deskewedBoxes.map { BoxDump(text: $0.text, x: $0.x, y: $0.y, w: $0.w, h: $0.h) }
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(dumpBoxes)
            AccountingOrchestrator.shared.lastBoxesJson = jsonData
        } catch {}
        
        print("[CLUSTER] === START === boxes=\(deskewedBoxes.count), medianHeight=\(medianHeight), theta=\(theta)")
        
        // === 2. Identify CUI/CIF Anchors (using deskewed coordinates) ===
        func isBuyerText(_ text: String) -> Bool {
            let t = text.uppercased()
            return t.contains("CLIENT") || t.contains("CUMP") || t.contains("BENEF") || t.contains("CNP")
        }
        
        func isCuiAnchor(_ box: OCRBoxItem) -> Bool {
            if isBuyerText(box.text) { return false }
            let upper = box.text.uppercased()
            if upper.contains("%") { return false }
            
            // Check if it has seller keywords
            let sellerKeywords = ["CIF", "CUI", "CODFISCAL", "FISCAL", "COD FISCAL"]
            let cleanText = upper.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
            for kw in sellerKeywords {
                let cleanKw = kw.replacingOccurrences(of: " ", with: "")
                if cleanText.contains(cleanKw) {
                    return true
                }
            }
            
            // Or contains valid CUI and not a buyer box
            if let cui = extractCUI(from: box.text) {
                if !isBuyerCUIBox(box, in: deskewedBoxes, medianHeight: CGFloat(medianHeight)) {
                    return true
                }
            }
            return false
        }
        
        var rawAnchors: [OCRBoxItem] = []
        for box in deskewedBoxes {
            if isCuiAnchor(box) {
                rawAnchors.append(box)
            }
        }
        
        // Deduplicate anchors close to each other
        var cuiAnchors: [OCRBoxItem] = []
        for a in rawAnchors {
            var isDup = false
            for u in cuiAnchors {
                let dx = abs(u.x - a.x)
                let dy = abs(u.y - a.y)
                if dx < medianHeight * 5.0 && dy < medianHeight * 3.0 {
                    isDup = true
                    break
                }
            }
            if !isDup {
                cuiAnchors.append(a)
                print("[CLUSTER] Anchor: '\(a.text)' x=\(Int(a.x)) y=\(Int(a.y))")
            }
        }
        print("[CLUSTER] Total unique anchors: \(cuiAnchors.count)")
        
        // === 3. Graph-Based (Single-Linkage) Clustering ===
        struct Point {
            let x: Double
            let y: Double
        }
        
        func getCorners(_ box: OCRBoxItem) -> [Point] {
            if let r = box.rect {
                return [
                    Point(x: r.topLeft_x, y: r.topLeft_y),
                    Point(x: r.topRight_x, y: r.topRight_y),
                    Point(x: r.bottomLeft_x, y: r.bottomLeft_y),
                    Point(x: r.bottomRight_x, y: r.bottomRight_y)
                ]
            } else {
                return [
                    Point(x: box.x, y: box.y),
                    Point(x: box.x + box.w, y: box.y),
                    Point(x: box.x, y: box.y + box.h),
                    Point(x: box.x + box.w, y: box.y + box.h)
                ]
            }
        }
        
        let n = deskewedBoxes.count
        var cornersList = deskewedBoxes.map { getCorners($0) }
        
        var minCornerDist = [[Double]](repeating: [Double](repeating: 0.0, count: n), count: n)
        var adj = [[Int]](repeating: [], count: n)
        
        let distThreshold = 4.0 * medianHeight
        
        for i in 0..<n {
            for j in (i+1)..<n {
                var dMin = Double.infinity
                for p1 in cornersList[i] {
                    for p2 in cornersList[j] {
                        let d = sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2))
                        if d < dMin {
                            dMin = d
                        }
                    }
                }
                minCornerDist[i][j] = dMin
                minCornerDist[j][i] = dMin
                
                if dMin < distThreshold {
                    adj[i].append(j)
                    adj[j].append(i)
                }
            }
        }
        
        // Find connected components using BFS
        var visited = [Bool](repeating: false, count: n)
        var components: [[Int]] = []
        
        for i in 0..<n {
            if !visited[i] {
                var comp: [Int] = []
                var q: [Int] = [i]
                visited[i] = true
                
                var head = 0
                while head < q.count {
                    let u = q[head]
                    head += 1
                    comp.append(u)
                    
                    for v in adj[u] {
                        if !visited[v] {
                            visited[v] = true
                            q.append(v)
                        }
                    }
                }
                components.append(comp)
            }
        }
        
        // === 4. Partition components with multiple anchors using Dijkstra ===
        var finalClusters: [[OCRBoxItem]] = []
        
        for comp in components {
            // Find which anchors are in this component
            var compAnchors: [Int] = []
            for node in comp {
                let box = deskewedBoxes[node]
                if cuiAnchors.contains(where: { $0.x == box.x && $0.y == box.y && $0.text == box.text }) {
                    compAnchors.append(node)
                }
            }
            
            if compAnchors.count <= 1 {
                let clusterBoxes = comp.map { deskewedBoxes[$0] }
                finalClusters.append(clusterBoxes)
            } else {
                // Multi-source Dijkstra partitioning
                var dist = [Int: Double]()
                var owner = [Int: Int]()
                
                for node in comp {
                    dist[node] = Double.infinity
                    owner[node] = -1
                }
                
                // Initialize anchors
                for (m, anchorNode) in compAnchors.enumerated() {
                    dist[anchorNode] = 0.0
                    owner[anchorNode] = m
                }
                
                var queue = Set(comp)
                while !queue.isEmpty {
                    var u: Int? = nil
                    var minDist = Double.infinity
                    for node in queue {
                        if let d = dist[node], d < minDist {
                            minDist = d
                            u = node
                        }
                    }
                    
                    guard let uNode = u else { break }
                    queue.remove(uNode)
                    
                    let uOwner = owner[uNode]!
                    let uDist = dist[uNode]!
                    
                    for v in adj[uNode] {
                        if queue.contains(v) {
                            let weight = minCornerDist[uNode][v]
                            let alt = uDist + weight
                            if let vDist = dist[v], alt < vDist {
                                dist[v] = alt
                                owner[v] = uOwner
                            }
                        }
                    }
                }
                
                // Group nodes by owner
                var partitioned = [[Int]](repeating: [], count: compAnchors.count)
                for node in comp {
                    let own = owner[node] ?? 0
                    let index = (own >= 0 && own < compAnchors.count) ? own : 0
                    partitioned[index].append(node)
                }
                
                for subComp in partitioned {
                    if !subComp.isEmpty {
                        let clusterBoxes = subComp.map { deskewedBoxes[$0] }
                        finalClusters.append(clusterBoxes)
                    }
                }
            }
        }
        
        var filteredClusters = finalClusters.filter { $0.count >= 3 }
        if filteredClusters.isEmpty {
            filteredClusters = [deskewedBoxes]
        }
        
        filteredClusters.sort { c1, c2 in
            let y1 = c1.map { $0.y }.min() ?? 0.0
            let y2 = c2.map { $0.y }.min() ?? 0.0
            let x1 = c1.map { $0.x }.min() ?? 0.0
            let x2 = c2.map { $0.x }.min() ?? 0.0
            if abs(y1 - y2) < medianHeight * 5.0 {
                return x1 < x2
            }
            return y1 < y2
        }
        
        print("[CLUSTER] === DONE (Single-Linkage Graph) === Returning \(filteredClusters.count) clusters")
        for (i, c) in filteredClusters.enumerated() {
            let minY = c.map { $0.y }.min() ?? 0.0
            let minX = c.map { $0.x }.min() ?? 0.0
            print("[CLUSTER]   Cluster \(i): \(c.count) boxes, topLeft=(\(Int(minX)),\(Int(minY)))")
        }
        
        return filteredClusters
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
    
    // Ignore 10-digit numbers starting with "07", "02", or "03" (phone numbers)
    if cui.count == 10 {
        if cui.hasPrefix("07") || cui.hasPrefix("02") || cui.hasPrefix("03") {
            return false
        }
    }
    
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

func containsRefinedRo(_ text: String) -> Bool {
    let upper = text.uppercased()
    let pattern = "\\bRO\\d+|\\bRO\\b"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
    let range = NSRange(location: 0, length: upper.utf16.count)
    return regex.firstMatch(in: upper, options: [], range: range) != nil
}

func extractCUI(from text: String) -> String? {
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

func parseFormattedAmount(_ text: String) -> Double? {
    var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
    cleaned = cleaned.replacingOccurrences(of: " ", with: "")
    
    let separators: [Character] = [".", ","]
    var lastSepIdx: String.Index? = nil
    for idx in cleaned.indices.reversed() {
        if separators.contains(cleaned[idx]) {
            lastSepIdx = idx
            break
        }
    }
    
    if let sepIdx = lastSepIdx {
        let afterSep = cleaned[sepIdx...]
        let digitsAfter = afterSep.dropFirst().filter { $0.isNumber }
        let charsAfterCount = afterSep.count - 1
        
        if charsAfterCount == 1 || charsAfterCount == 2 {
            let integerPart = String(cleaned[..<sepIdx]).filter { $0.isNumber }
            let decimalPart = String(digitsAfter)
            if let doubleVal = Double("\(integerPart).\(decimalPart)") {
                return doubleVal
            }
        } else {
            let allDigits = cleaned.filter { $0.isNumber }
            return Double(allDigits)
        }
    } else {
        let allDigits = cleaned.filter { $0.isNumber }
        return Double(allDigits)
    }
    return nil
}
