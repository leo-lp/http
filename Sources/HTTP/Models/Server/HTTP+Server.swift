#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

import Transport

public typealias BasicServer = Server<TCPServerStream, Parser<Request>, Serializer<Response>>

public final class Server<
    ServerStreamType: ServerStream,
    Parser: TransferParser,
    Serializer: TransferSerializer>: ServerProtocol
    where
    Parser.MessageType == Request,
    Serializer.MessageType == Response
 {

    let server: ServerStreamType

    public let host: String
    public let port: Int
    public let securityLayer: SecurityLayer

    public init(host: String = "0.0.0.0", port: Int = 8080, securityLayer: SecurityLayer = .none) throws {
        self.host = host
        self.port = port
        self.securityLayer = securityLayer

        do {
            server = try ServerStreamType(host: host, port: port, securityLayer: securityLayer)
        } catch {
            throw ServerError.bind(host: host, port:port, error)
        }
    }

    public func start(responder: Responder, errors: @escaping ServerErrorHandler) throws {
        // no throwing inside of the loop
        while true {
            let stream: Stream

            do {
                stream = try server.accept()
            } catch {
                errors(.accept(error))
                continue
            }

            do {
                _ = try background {
                    do {
                        try self.respond(stream: stream, responder: responder)
                    } catch {
                        errors(.dispatch(error))
                    }
                }
            } catch {
                errors(.dispatch(error))
            }
        }
    }

    private func respond(stream: Stream, responder: Responder) throws {
        let stream = StreamBuffer(stream)
        try stream.setTimeout(30)

        let parser = Parser(stream: stream)
        let serializer = Serializer(stream: stream)

        defer {
            try? stream.close()
        }

        var keepAlive = false
        repeat {
            let request: Request
            do {
                request = try parser.parse()
            } catch ParserError.streamEmpty {
                // if stream is empty, it's time to
                // close the connection
                break
            } catch {
                throw error
            }

            keepAlive = request.keepAlive
            let response = try responder.respond(to: request)
            try serializer.serialize(response)
            try response.onComplete?(stream)
        } while keepAlive && !stream.closed
    }
}
