//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Foundation

struct CastYouTubeHTTPRequest: Sendable {
    var url: URL
    var query: [URLQueryItem]
    var headers: [String: String]
    var form: [String: String]

    init(
        url: URL,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        form: [String: String] = [:]
    ) {
        self.url = url
        self.query = query
        self.headers = headers
        self.form = form
    }
}

struct CastYouTubeHTTPResponse: Sendable {
    var statusCode: Int
    var body: Data
}

protocol CastYouTubeHTTPClient: Sendable {
    func post(_ request: CastYouTubeHTTPRequest, timeout: TimeInterval) async throws -> CastYouTubeHTTPResponse
}

struct CastYouTubeURLSessionHTTPClient: CastYouTubeHTTPClient {
    func post(_ request: CastYouTubeHTTPRequest, timeout: TimeInterval) async throws -> CastYouTubeHTTPResponse {
        var components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)
        components?.queryItems = request.query.isEmpty ? nil : request.query

        guard let url = components?.url else {
            throw CastError.invalidArgument("Invalid YouTube HTTP request URL")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeout
        urlRequest.httpBody = formURLEncodedData(request.form)

        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CastError.invalidResponse("YouTube HTTP response was not an HTTPURLResponse")
            }
            return .init(statusCode: httpResponse.statusCode, body: data)
        } catch let error as URLError where error.code == .timedOut {
            throw CastError.timeout(operation: "YouTube MDX HTTP request")
        } catch {
            throw CastError.requestFailed(code: nil, message: String(describing: error))
        }
    }

    private func formURLEncodedData(_ form: [String: String]) -> Data? {
        guard form.isEmpty == false else {
            return nil
        }

        let body = form
            .sorted(by: { $0.key < $1.key })
            .map { key, value in
                "\(formEncoded(key))=\(formEncoded(value))"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private func formEncoded(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._* ")
        return value
            .addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: " ", with: "+") ?? value
    }
}
