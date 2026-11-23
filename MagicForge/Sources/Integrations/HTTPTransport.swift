import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One HTTP request, independent of URLSession so tests can inspect it.
public struct HTTPRequestData: Sendable, Equatable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data
    /// Seconds.
    public var timeout: TimeInterval

    public init(url: URL, method: String = "POST", headers: [String: String] = [:], body: Data = Data(),
                timeout: TimeInterval = 30) {
        self.url = url; self.method = method; self.headers = headers; self.body = body; self.timeout = timeout
    }
}

public struct HTTPResponseData: Sendable, Equatable {
    public var status: Int
    public var body: Data
    public init(status: Int, body: Data) { self.status = status; self.body = body }
}

public enum HTTPTransportError: Error, Equatable, Sendable {
    case timedOut
    case cancelled
    /// Could not connect, TLS failure, connection lost, … (description is safe to show).
    case network(String)
}

/// Sends a request and returns the raw response. Implementations must not retry, cache or log bodies.
public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequestData) async throws -> HTTPResponseData
}

/// URLSession-backed transport: ephemeral session, no cache, no cookies, no stored credentials.
public final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        session = URLSession(configuration: configuration)
    }

    deinit { session.invalidateAndCancel() }

    public func send(_ request: HTTPRequestData) async throws -> HTTPResponseData {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = request.timeout
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        urlRequest.httpShouldHandleCookies = false
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }

        let box = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HTTPResponseData, Error>) in
                let task = session.dataTask(with: urlRequest) { data, response, error in
                    if let error {
                        continuation.resume(throwing: Self.transportError(from: error))
                    } else if let http = response as? HTTPURLResponse {
                        continuation.resume(returning: HTTPResponseData(status: http.statusCode, body: data ?? Data()))
                    } else {
                        continuation.resume(throwing: HTTPTransportError.network("The server sent no HTTP response."))
                    }
                }
                box.set(task)
                task.resume()
            }
        } onCancel: {
            box.cancel()
        }
    }

    private static func transportError(from error: Error) -> HTTPTransportError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return .timedOut
            case .cancelled: return .cancelled
            default: return .network(urlError.localizedDescription)
            }
        }
        return .network(error.localizedDescription)
    }

    /// Holds the data task so cancellation can reach it, including cancellation that arrives
    /// before the task was created.
    private final class TaskBox: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionDataTask?
        private var isCancelled = false

        func set(_ task: URLSessionDataTask) {
            lock.lock()
            self.task = task
            let cancelNow = isCancelled
            lock.unlock()
            if cancelNow { task.cancel() }
        }

        func cancel() {
            lock.lock()
            isCancelled = true
            let task = self.task
            lock.unlock()
            task?.cancel()
        }
    }
}
