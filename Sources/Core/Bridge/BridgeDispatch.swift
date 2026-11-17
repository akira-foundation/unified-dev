import Foundation

public struct BridgeDispatch: Sendable {
    private let store: Store
    private let toolbox: BridgeToolbox
    private let identity: BridgeIdentity

    public init(store: Store, identity: BridgeIdentity, toolbox: BridgeToolbox = .standard) {
        self.store = store
        self.identity = identity
        self.toolbox = toolbox
    }

    public static let serverVersion = "\(BridgeProtocol.version).0.0"

    public func respond(to line: String) async -> String? {
        guard let request = MCPRequest.decode(line) else {
            return nil
        }
        guard let response = await respond(to: request) else { return nil }
        return response.line()
    }

    public func respond(to request: MCPRequest) async -> MCPResponse? {
        guard let id = request.replyID else { return nil }

        switch request.method {
        case "initialize":
            return .result(id: id, initialize(request))
        case "ping":
            return .result(id: id, .object([:]))
        case "tools/list":
            let tools = await toolbox.tools(for: identity, store: store).map(\.listing)
            return .result(id: id, .object(["tools": .array(tools)]))
        case "tools/call":
            return await callTool(request, id: id)
        default:
            return .failure(
                id: id,
                code: MCPErrorCode.methodNotFound,
                message: "\(BridgeRegistration.serverName) does not implement \(request.method)"
            )
        }
    }

    private func initialize(_ request: MCPRequest) -> JSONValue {
        let requested = request.param("protocolVersion")
        return .object([
            "protocolVersion": requested ?? .string("2025-06-18"),
            "capabilities": .object(["tools": .object([:])]),
            "serverInfo": .object([
                "name": .string(BridgeRegistration.serverName),
                "version": .string(Self.serverVersion),
            ]),
        ])
    }

    private func callTool(_ request: MCPRequest, id: JSONValue) async -> MCPResponse {
        guard let name = request.stringParam("name") else {
            return .failure(
                id: id,
                code: MCPErrorCode.invalidParams,
                message: "tools/call needs a tool name"
            )
        }
        guard let handler = await toolbox.handler(named: name, for: identity, store: store) else {
            return .failure(
                id: id,
                code: MCPErrorCode.methodNotFound,
                message: "\(BridgeRegistration.serverName) has no tool called \(name)"
            )
        }
        let call = MCPRequest(id: request.id, method: name, params: request.param("arguments"))
        let result = await handler.call(call, as: identity, store: store)
        return .result(id: id, result.content)
    }
}
