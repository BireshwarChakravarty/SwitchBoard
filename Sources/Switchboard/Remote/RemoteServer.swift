import Foundation
import Network

/// A minimal HTTP server for the iPhone remote, on the local network only.
///
/// One request per connection (`Connection: close`), requests capped at
/// `HTTPParser.maximumSize`, and connections that stall are dropped. All of
/// its state lives on its own serial queue.
final class RemoteServer: @unchecked Sendable {
    typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    private let queue = DispatchQueue(label: "Switchboard.remote")
    private var listener: NWListener?
    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    /// Start listening. `onState` reports readiness or failure on the main queue.
    func start(port: UInt16, onState: @escaping @Sendable (Result<Void, Error>) -> Void) {
        queue.async {
            guard self.listener == nil else { return }
            do {
                guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
                    throw NWError.posix(.EINVAL)
                }
                let parameters = NWParameters.tcp
                parameters.allowLocalEndpointReuse = true
                let listener = try NWListener(using: parameters, on: endpointPort)
                listener.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready:
                        Log.app.info("Remote: listening on port \(port)")
                        DispatchQueue.main.async { onState(.success(())) }
                    case .failed(let error):
                        Log.app.error("Remote: listener failed: \(error.localizedDescription, privacy: .public)")
                        self?.stop()
                        DispatchQueue.main.async { onState(.failure(error)) }
                    default:
                        break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.serve(connection)
                }
                self.listener = listener
                listener.start(queue: self.queue)
            } catch {
                Log.app.error("Remote: couldn't listen: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async { onState(.failure(error)) }
            }
        }
    }

    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
        }
    }

    // MARK: Connections

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        // Drop connections that don't finish a request promptly.
        queue.asyncAfter(deadline: .now() + 10) { [weak connection] in
            connection?.cancel()
        }
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }

            switch HTTPParser.parse(buffer) {
            case .complete(let request):
                self.respond(to: request, on: connection)
            case .invalid:
                let status = buffer.count > HTTPParser.maximumSize ? 413 : 400
                self.send(.error("Bad request", status: status), on: connection)
            case .incomplete:
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    self.receive(on: connection, buffer: buffer)
                }
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        let handler = self.handler
        Task {
            var response = await handler(request)
            response.omitsBody = request.method == "HEAD"
            self.queue.async { self.send(response, on: connection) }
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { _ in connection.cancel() })
    }
}
