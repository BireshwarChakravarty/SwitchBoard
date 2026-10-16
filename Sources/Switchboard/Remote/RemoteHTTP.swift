import Foundation

/// A parsed HTTP/1.1 request. Just enough of HTTP for the iPhone remote:
/// one request per connection, a small body, no chunked encoding.
struct HTTPRequest: Sendable, Equatable {
    var method: String
    /// Percent-decoded path components, e.g. ["api", "screens", "ARZOPA", "off"].
    var pathComponents: [String]
    var query: [String: String]
    /// Header names in lower case.
    var headers: [String: String]
    var body: Data
}

enum HTTPParseResult: Equatable {
    /// More bytes are needed.
    case incomplete
    /// Not a request we accept (malformed, or too large).
    case invalid
    case complete(HTTPRequest)
}

enum HTTPParser {
    /// Largest request accepted, headers and body together.
    static let maximumSize = 64 * 1024

    static func parse(_ data: Data) -> HTTPParseResult {
        guard data.count <= maximumSize else { return .invalid }
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: separator) else { return .incomplete }

        guard let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else {
            return .invalid
        }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        if headers["transfer-encoding"] != nil { return .invalid }

        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0 else { return .invalid }
        let bodyStart = headerEnd.upperBound
        guard data.count - (bodyStart - data.startIndex) >= length else { return .incomplete }
        let body = data[bodyStart..<(bodyStart + length)]

        let target = String(requestLine[1])
        guard target.hasPrefix("/"), let components = URLComponents(string: target) else { return .invalid }
        let path = components.percentEncodedPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.removingPercentEncoding ?? String($0) }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }

        return .complete(HTTPRequest(
            method: String(requestLine[0]).uppercased(),
            pathComponents: path,
            query: query,
            headers: headers,
            body: Data(body)
        ))
    }
}

struct HTTPResponse: Sendable {
    var status: Int
    var contentType: String
    var body: Data
    var extraHeaders: [String: String] = [:]

    static func json<T: Encodable>(_ value: T, status: Int = 200) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = (try? encoder.encode(value)) ?? Data("{}".utf8)
        return HTTPResponse(status: status, contentType: "application/json; charset=utf-8", body: body)
    }

    /// `{"error": "…", "message": "…"}` with the given status. `message` is
    /// what Shortcuts reads out, for errors and successes alike.
    static func error(_ message: String, status: Int) -> HTTPResponse {
        json(["error": message, "message": message], status: status)
    }

    var serialized: Data {
        var head = "HTTP/1.1 \(status) \(Self.reason(for: status))\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "X-Content-Type-Options: nosniff\r\n"
        head += "Connection: close\r\n"
        for (name, value) in extraHeaders.sorted(by: { $0.key < $1.key }) {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"
        return Data(head.utf8) + body
    }

    static func reason(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 409: "Conflict"
        case 413: "Payload Too Large"
        case 429: "Too Many Requests"
        default: "Error"
        }
    }
}
