import Foundation

public struct BridgeTool: Sendable, Hashable {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue

    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    public static let noArguments = JSONValue.object([
        "type": .string("object"),
        "properties": .object([:]),
        "required": .array([]),
    ])

    public var listing: JSONValue {
        .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": inputSchema,
        ])
    }
}

public struct BridgeToolResult: Sendable, Hashable {
    public let text: String
    public let isError: Bool
    public let image: BridgeToolImage?

    public init(text: String, isError: Bool = false, image: BridgeToolImage? = nil) {
        self.text = text
        self.isError = isError
        self.image = image
    }

    public static func picture(_ image: BridgeToolImage, saying text: String) -> BridgeToolResult {
        BridgeToolResult(text: text, isError: false, image: image)
    }

    public static func failure(_ text: String) -> BridgeToolResult {
        BridgeToolResult(text: text, isError: true)
    }

    public static func json(_ value: JSONValue) -> BridgeToolResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else {
            return .failure("Unified Dev could not render this answer as JSON.")
        }
        return BridgeToolResult(text: String(decoding: data, as: UTF8.self))
    }

    public var content: JSONValue {
        var blocks: [JSONValue] = [.object(["type": .string("text"), "text": .string(text)])]
        if let image { blocks.append(image.content) }
        return .object([
            "content": .array(blocks),
            "isError": .bool(isError),
        ])
    }
}

public struct BridgeToolImage: Sendable, Hashable {
    public let data: Data
    public let mimeType: String

    public static let maximumBytes = 4 * 1_024 * 1_024

    public init(png: Data) {
        data = png
        mimeType = "image/png"
    }

    public var isTooLarge: Bool { data.count > Self.maximumBytes }

    var content: JSONValue {
        .object([
            "type": .string("image"),
            "data": .string(data.base64EncodedString()),
            "mimeType": .string(mimeType),
        ])
    }
}

public protocol BridgeToolHandling: Sendable {
    var tool: BridgeTool { get }
    var roles: Set<BridgeRole> { get }

    func call(_ request: MCPRequest, as identity: BridgeIdentity, store: Store) async -> BridgeToolResult

    func isServed(to identity: BridgeIdentity, store: Store) async -> Bool
}

extension BridgeToolHandling {
    public func isServed(to identity: BridgeIdentity, store: Store) async -> Bool { true }
}
