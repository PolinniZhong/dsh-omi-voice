import Foundation

enum TTSMessageType: UInt8, Sendable {
    case fullClientRequest = 0x1
    case audioOnlyResponse = 0xB
    case errorResponse = 0xF
}

enum TTSBinaryFrame: Sendable {
    case audio(Data, sequence: Int32, isFinal: Bool)
    case error(Data)
    case other(type: UInt8, payload: Data)
}

struct TTSBinaryHeader: Sendable {
    let protocolVersion: UInt8
    let headerSizeWords: UInt8
    let messageType: UInt8
    let messageFlags: UInt8
    let serialization: UInt8
    let compression: UInt8

    static func parse(_ data: Data) throws -> TTSBinaryHeader {
        guard data.count >= 4 else { throw TTSProtocolError.truncatedHeader }
        let first = data[data.startIndex]
        let second = data[data.startIndex + 1]
        let third = data[data.startIndex + 2]
        return TTSBinaryHeader(
            protocolVersion: first >> 4,
            headerSizeWords: first & 0x0F,
            messageType: second >> 4,
            messageFlags: second & 0x0F,
            serialization: third >> 4,
            compression: third & 0x0F
        )
    }
}

enum TTSProtocolError: LocalizedError {
    case truncatedHeader
    case unsupportedProtocol(UInt8)
    case unsupportedMessageType(UInt8)
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .truncatedHeader: return "TTS 二进制帧头长度不足。"
        case .unsupportedProtocol(let value): return "不支持的 TTS 协议版本：\(value)。"
        case .unsupportedMessageType(let value): return "不支持的 TTS 消息类型：\(value)。"
        case .invalidPayload: return "TTS 二进制帧载荷格式无效。"
        }
    }
}

extension TTSBinaryProtocol {
    static func makeClientRequest(payload: Data) -> Data {
        var frame = Data([0x11, 0x10, 0x10, 0x00])
        frame.append(contentsOf: UInt32(payload.count).bigEndianBytes)
        frame.append(payload)
        return frame
    }

    static func parseServerFrame(_ data: Data) throws -> TTSBinaryFrame {
        let header = try TTSBinaryHeader.parse(data)
        guard header.protocolVersion == 1 else {
            throw TTSProtocolError.unsupportedProtocol(header.protocolVersion)
        }
        let offset = Int(header.headerSizeWords) * 4
        guard data.count >= offset else { throw TTSProtocolError.truncatedHeader }
        let payload = data.subdata(in: offset..<data.count)

        switch header.messageType {
        case TTSMessageType.audioOnlyResponse.rawValue:
            guard payload.count >= 8 else { throw TTSProtocolError.invalidPayload }
            let sequence = Int32(bigEndianBytes: payload.prefix(4))
            let size = Int(UInt32(bigEndianBytes: payload.subdata(in: 4..<8)))
            guard payload.count >= 8 + size else { throw TTSProtocolError.invalidPayload }
            let audio = payload.subdata(in: 8..<(8 + size))
            return .audio(audio, sequence: sequence, isFinal: header.messageFlags == 2 || header.messageFlags == 3)
        case TTSMessageType.errorResponse.rawValue:
            return .error(payload)
        default:
            return .other(type: header.messageType, payload: payload)
        }
    }
}

enum TTSBinaryProtocol {}

private extension UInt32 {
    var bigEndianBytes: [UInt8] {
        let value = bigEndian
        return [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
    }
}

private extension Int32 {
    init(bigEndianBytes data: Data) {
        let value = data.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        self.init(bitPattern: value)
    }
}

private extension UInt32 {
    init(bigEndianBytes data: Data) {
        self = data.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}
