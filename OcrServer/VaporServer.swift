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
                let clusters = AccountingOrchestrator.shared.clusterBoxes(boxes)
                
                for cluster in clusters {
                    let clusterResults = await AccountingOrchestrator.shared.processOcrResult(boxes: cluster, buyerCui: upload.buyer_cui)
                    accountingDataArray.append(contentsOf: clusterResults)
                }
                
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
        // 1. Cautare Spatiala Inteligenta 2D (Fuzzy)
        let cuiKeywords = ["CIF", "CUI", "CODFISCAL", "RO"]
        var candidateBoxes: [OCRBoxItem] = []
        
        for box in boxes {
            let cleanText = box.text.uppercased().replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
            
            // Excludem CUI-urile de client (asa cum am facut si la ancore)
            if cleanText.contains("CLIENT") || cleanText.contains("CUMP") || cleanText.contains("BENEF") || cleanText.contains("CNP") {
                continue
            }
            
            if cuiKeywords.contains(where: { cleanText.contains($0) || (cleanText.count <= $0.count + 2 && cleanText.isFuzzyMatch($0, tolerance: 1)) }) {
                candidateBoxes.append(box)
            }
        }
        
        // Verificam textul din interiorul cutiilor gasite (poate CUI-ul e in aceeasi cutie: "CIF RO123456")
        for box in candidateBoxes {
            let text = box.text.uppercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ".", with: "")
            let numbersOnly = text.filter { $0.isNumber }
            if isValidCUI(cui: numbersOnly) {
                result.cui = numbersOnly
                result.cuiRequiresVerification = false
                await verifyWithANAF(cui: numbersOnly, result: &result)
                // Restabilim CUI-ul chiar daca ANAF zice fals (ANAF poate da timeout/eroare), noi am extras bine din poza
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
        
        // 2. Fallback la Regex-ul clasic (daca geometria a esuat sau OCR-ul a unit totul aiurea)
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
        
        result.cuiRequiresVerification = true
    }
    
    private func isValidCUI(cui: String) -> Bool {
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
        
        // --- SPATIAL TOTAL EXTRACTION ---
        let totalKeywords = ["TOTAL", "SUMA", "ACHITAT"]
        var totalFound = false
        
        for box in boxes {
            let cleanText = box.text.uppercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ":", with: "")
            if totalKeywords.contains(where: { cleanText.contains($0) || (cleanText.count <= $0.count + 2 && cleanText.isFuzzyMatch($0, tolerance: 1)) }) {
                // Cauta numere pe aceeasi linie (axa Y similara), la dreapta
                let yTol = max(box.h * 0.6, 15.0)
                let lineBoxes = boxes.filter {
                    ($0.x != box.x || $0.y != box.y) &&
                    abs($0.y - box.y) < yTol &&
                    $0.x > box.x - box.w * 0.5
                }.sorted { $0.x < $1.x }
                
                let lineTextForCheck = lineBoxes.map { $0.text.uppercased() }.joined(separator: " ")
                if lineTextForCheck.contains("TVA") {
                    continue // Ignoram liniile "TOTAL TVA"
                }
                
                for lBox in lineBoxes {
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
            let totalPattern = "(?:TOTAL|SUMA|ACHITAT|REST)\\s*(?:LEI)?\\s*[:]*\\s*([0-9]+[.,][0-9]{2})"
            if let regex = try? NSRegularExpression(pattern: totalPattern, options: []),
               let match = regex.firstMatch(in: fullText, options: [], range: NSRange(location: 0, length: fullText.utf16.count)) {
                let matchedString = (fullText as NSString).substring(with: match.range(at: 1))
                if let val = Double(matchedString.replacingOccurrences(of: ",", with: ".")) {
                    result.totalAmount = val
                    result.totalRequiresVerification = false
                }
            }
        }
        
        // Ultimul Fallback: ia cel mai mare numar
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
            // --- SPATIAL TVA EXTRACTION ---
            var foundVatAmounts: [Double] = []
            var foundVatPercentages: [String] = []
            
            for box in boxes {
                let cleanText = box.text.uppercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ":", with: "")
                if cleanText.isFuzzyMatch("TVA", tolerance: 1) || cleanText.contains("TVA") {
                    let yTol = max(box.h * 0.6, 15.0)
                    let lineBoxes = boxes.filter {
                        abs($0.y - box.y) < yTol &&
                        $0.x > box.x - box.w * 0.5
                    }.sorted { $0.x < $1.x }
                    
                    let lineText = lineBoxes.map { $0.text }.joined(separator: " ")
                    let vatPattern = "([0-9]{1,2})(?:[,.][0-9]{1,2})?\\s*[%][^0-9]{0,15}?([0-9]+[,.][0-9]{2})"
                    
                    if let regex = try? NSRegularExpression(pattern: vatPattern, options: []) {
                        let nsString = lineText as NSString
                        if let match = regex.firstMatch(in: lineText, options: [], range: NSRange(location: 0, length: nsString.length)), match.numberOfRanges > 2 {
                            let pctString = nsString.substring(with: match.range(at: 1))
                            let valString = nsString.substring(with: match.range(at: 2)).replacingOccurrences(of: ",", with: ".")
                            if let val = Double(valString) {
                                foundVatPercentages.append("\(pctString)%")
                                foundVatAmounts.append(val)
                            }
                        }
                    }
                }
            }
            
            // Fallback TVA
            if foundVatAmounts.isEmpty {
                let totalVatPattern = "TOTAL\\s*TVA[^0-9]{0,15}?([0-9]+[,.][0-9]{2})"
                if let regex = try? NSRegularExpression(pattern: totalVatPattern, options: []),
                   let match = regex.firstMatch(in: fullText, options: [], range: NSRange(location: 0, length: fullText.utf16.count)), match.numberOfRanges > 1 {
                    let valString = (fullText as NSString).substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")
                    if let val = Double(valString) {
                        foundVatAmounts.append(val)
                        foundVatPercentages.append("Mixt")
                    }
                }
            }
            
            if !foundVatAmounts.isEmpty {
                var breakdowns: [VatBreakdown] = []
                for i in 0..<foundVatAmounts.count {
                    let pctStr = foundVatPercentages[i].replacingOccurrences(of: "%", with: "")
                    let pct = Double(pctStr) ?? 19.0
                    let val = foundVatAmounts[i]
                    // Daca e Mixt, calculul nu se poate face doar din TVA, dar e fallback.
                    let base = pct > 0 ? (val * 100.0) / pct : (result.totalAmount ?? val)
                    let roundedBase = (base * 100).rounded() / 100
                    breakdowns.append(VatBreakdown(percentage: foundVatPercentages[i], vatAmount: val, baseAmount: roundedBase))
                }
                result.vatBreakdowns = breakdowns
                
                let sumVat = foundVatAmounts.reduce(0, +)
                result.vatAmount = (sumVat * 100).rounded() / 100
                result.vatPercentages = Array(Set(foundVatPercentages)).joined(separator: ", ")
                result.vatRequiresVerification = false
                
                if let total = result.totalAmount {
                    result.baseAmount = ((total - result.vatAmount!) * 100).rounded() / 100
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
                if !fullText.contains(bCui) {
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
                splitCopy.totalAmount = ((b.baseAmount + b.vatAmount) * 100).rounded() / 100
                // Curatam vectorul intern
                splitCopy.vatBreakdowns = nil
                splitResults.append(splitCopy)
            }
            return splitResults
        }
        
        return [result]
    }
    
    // Separa cutiile de text in documente distincte
    func clusterBoxes(_ boxes: [OCRBoxItem]) -> [[OCRBoxItem]] {
        guard boxes.count > 1 else { return [boxes] }
        
        let sortedHeights = boxes.map { $0.h }.sorted()
        let medianHeight = sortedHeights[sortedHeights.count / 2]
        
        // 1. Anchor-based clustering (bazat pe CUI/CIF Vânzător)
        let fullText = boxes.map { $0.text }.joined(separator: " ").uppercased()
        let cuiPattern = "(?i)(?:CUI|CIF|FISCAL[A-Z]*|C\\.I\\.F|C\\.F)\\s*[:.]?\\s*(?:RO)?\\s*([0-9]{5,10})"
        var foundCuis: [String] = []
        if let regex = try? NSRegularExpression(pattern: cuiPattern, options: []) {
            let nsStr = fullText as NSString
            let results = regex.matches(in: fullText, options: [], range: NSRange(location: 0, length: nsStr.length))
            for match in results {
                if match.numberOfRanges > 1 {
                    let cuiStr = nsStr.substring(with: match.range(at: 1))
                    if !foundCuis.contains(cuiStr) {
                        foundCuis.append(cuiStr)
                    }
                }
            }
        }
        
        var extractedAnchors: [(box: OCRBoxItem, cuiStr: String)] = []
        for box in boxes {
            let text = box.text.uppercased()
            let cleanText = text.replacingOccurrences(of: " ", with: "")
            
            // Excludem CUI-urile de client
            if text.contains("CLIENT") || text.contains("CUMP") || text.contains("BENEF") || text.contains("CNP") || text.contains("C.N.P") {
                continue
            }
            
            for cui in foundCuis {
                if cleanText.contains(cui) {
                    extractedAnchors.append((box, cui))
                    break
                }
            }
        }
        
        // Filtram ancorele pentru a pastra doar UNA per bon fizic
        var uniqueAnchors: [OCRBoxItem] = []
        var uniqueCuis: [String] = []
        for a in extractedAnchors {
            var isDuplicate = false
            for i in 0..<uniqueAnchors.count {
                let u = uniqueAnchors[i]
                let uCui = uniqueCuis[i]
                let dx = abs(u.x - a.box.x)
                let dy = abs(u.y - a.box.y)
                
                // Daca e acelasi CUI si e in aceeasi coloana (acelasi bon fizic)
                if uCui == a.cuiStr && dx < medianHeight * 10.0 {
                    isDuplicate = true
                    break
                }
                // Daca sunt prea aproape fizic (evitam dubla potrivire pe acelasi bloc de text care a fost impartit de OCR)
                if dx < medianHeight * 5.0 && dy < medianHeight * 2.0 {
                    isDuplicate = true
                    break
                }
            }
            if !isDuplicate {
                uniqueAnchors.append(a.box)
                uniqueCuis.append(a.cuiStr)
            }
        }
        
        var clusters: [[OCRBoxItem]] = []
        
        if uniqueAnchors.count > 1 {
            // Avem mai multe bonuri sigure! Aplicam Voronoi clustering cu penalizare orizontala
            var groups: [[OCRBoxItem]] = Array(repeating: [], count: uniqueAnchors.count)
            for box in boxes {
                var bestDist: CGFloat = .infinity
                var bestIdx = 0
                for (i, anchor) in uniqueAnchors.enumerated() {
                    let dx = abs(box.x - anchor.x)
                    var dy = box.y - anchor.y
                    
                    // Daca textul este DEASUPRA ancorei (dy negativ), penalizam enorm.
                    // CUI-ul e mereu sus, restul bonului e in jos.
                    if dy < -medianHeight * 2.0 {
                        dy = abs(dy) + 10000.0
                    } else {
                        dy = abs(dy)
                    }
                    
                    // Penalizam moderat distanta orizontala, ca textele indendate sa ramana la bonul lor
                    let dist = dx * 3.0 + dy
                    if dist < bestDist {
                        bestDist = dist
                        bestIdx = i
                    }
                }
                groups[bestIdx].append(box)
            }
            clusters = groups
        } else {
            // 2. Fallback: XY-Cut
            clusters = recursiveXYCut(boxes, medianHeight: medianHeight)
        }
        
        // Excludem gunoaiele (clustere cu doar 1-2 linii de text)
        clusters = clusters.filter { $0.count >= 3 }
        if clusters.isEmpty { return [boxes] }
        
        // Sortam clusterele (de sus in jos, stanga la dreapta)
        return clusters.sorted {
            if abs($0[0].y - $1[0].y) < medianHeight * 5.0 {
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
