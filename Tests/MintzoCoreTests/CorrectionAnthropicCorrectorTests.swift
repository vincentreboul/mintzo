import XCTest
@testable import MintzoCore

/// Intercepte toutes les requêtes de l'URLSession de test — AUCUN appel réseau réel.
private final class MockURLProtocol: URLProtocol {
    /// `nonisolated(unsafe)` : positionné avant chaque requête dans des tests séquentiels,
    /// lu par la stack URLSession — pas d'accès concurrent dans ce cadre.
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest, Data) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request, Self.bodyData(of: request))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    /// URLSession convertit httpBody en stream avant d'atteindre l'URLProtocol.
    private static func bodyData(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

private struct StubKeyProvider: KeyProviding {
    var key: String? = "sk-ant-test-key"

    func apiKey() throws -> String {
        guard let key else { throw AnthropicCorrectorError.missingAPIKey }
        return key
    }
}

final class CorrectionAnthropicCorrectorTests: XCTestCase {

    private var corrector: AnthropicCorrector {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return AnthropicCorrector(keyProvider: StubKeyProvider(), session: URLSession(configuration: config))
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private static func response(status: Int, url: URL) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    }

    func testSuccessfulCorrectionParsesTextBlocksAndSendsProperRequest() async throws {
        MockURLProtocol.handler = { request, body in
            // Requête : endpoint + headers + corps conformes à l'API Messages.
            XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")

            let json = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            XCTAssertEqual(json["model"] as? String, "claude-sonnet-4-6")
            XCTAssertEqual(json["temperature"] as? Double, 0)
            XCTAssertNotNil(json["max_tokens"] as? Int)
            XCTAssertTrue((json["system"] as? String)?.contains("Zuzentzaile") == true)
            let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.first?["role"] as? String, "user")
            XCTAssertEqual(messages.first?["content"] as? String, "kaixo maite")

            let payload = """
            {"content":[{"type":"text","text":"Kaixo, Maite!"}],"stop_reason":"end_turn"}
            """
            return (Self.response(status: 200, url: request.url!), Data(payload.utf8))
        }

        let output = try await corrector.correct("kaixo maite", language: .basque)
        XCTAssertEqual(output, "Kaixo, Maite!")
    }

    /// Dictionnaire personnalisé : les graphies transitent jusqu'au corps de la
    /// requête cloud (section « respecte ces graphies » du prompt système).
    func testProtectedWordsReachTheSystemPrompt() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let vocabCorrector = AnthropicCorrector(
            keyProvider: StubKeyProvider(),
            session: URLSession(configuration: config),
            protectedWords: ["Bitwip", "Maite"]
        )

        MockURLProtocol.handler = { request, body in
            let json = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            let system = try XCTUnwrap(json["system"] as? String)
            XCTAssertTrue(system.contains("Errespetatu ZEHAZKI grafia hauek"),
                          "Section graphies absente du prompt système cloud")
            XCTAssertTrue(system.contains("Bitwip, Maite."))

            let payload = """
            {"content":[{"type":"text","text":"Kaixo, Maite!"}],"stop_reason":"end_turn"}
            """
            return (Self.response(status: 200, url: request.url!), Data(payload.utf8))
        }

        let output = try await vocabCorrector.correct("kaixo maite", language: .basque)
        XCTAssertEqual(output, "Kaixo, Maite!")
    }

    func testHTTPErrorSurfacesStatusAndMessage() async {
        MockURLProtocol.handler = { request, _ in
            let payload = """
            {"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}
            """
            return (Self.response(status: 401, url: request.url!), Data(payload.utf8))
        }

        do {
            _ = try await corrector.correct("kaixo", language: .basque)
            XCTFail("Une erreur HTTP 401 doit lever")
        } catch let error as AnthropicCorrectorError {
            XCTAssertEqual(error, .httpError(status: 401, message: "invalid x-api-key"))
        } catch {
            XCTFail("Erreur inattendue : \(error)")
        }
    }

    func testRefusalStopReasonThrows() async {
        MockURLProtocol.handler = { request, _ in
            let payload = """
            {"content":[],"stop_reason":"refusal"}
            """
            return (Self.response(status: 200, url: request.url!), Data(payload.utf8))
        }

        do {
            _ = try await corrector.correct("kaixo", language: .basque)
            XCTFail("Un stop_reason refusal doit lever")
        } catch let error as AnthropicCorrectorError {
            XCTAssertEqual(error, .refused)
        } catch {
            XCTFail("Erreur inattendue : \(error)")
        }
    }

    func testMissingKeyThrowsWithoutNetworkCall() async {
        MockURLProtocol.handler = { _, _ in
            XCTFail("Aucune requête ne doit partir sans clé")
            throw URLError(.badURL)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let corrector = AnthropicCorrector(
            keyProvider: StubKeyProvider(key: nil),
            session: URLSession(configuration: config)
        )

        do {
            _ = try await corrector.correct("kaixo", language: .basque)
            XCTFail("Sans clé, correct doit lever")
        } catch let error as AnthropicCorrectorError {
            XCTAssertEqual(error, .missingAPIKey)
        } catch {
            XCTFail("Erreur inattendue : \(error)")
        }
    }
}
