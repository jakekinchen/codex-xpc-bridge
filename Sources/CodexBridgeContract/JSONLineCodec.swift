import Foundation

public enum JSONLineCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        var data = try JSONEncoder.codexBridge.encode(value)
        data.append(0x0A)
        return data
    }

    public static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        try encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let trimmed = if data.last == 0x0A { Data(data.dropLast()) } else { data }
        return try JSONDecoder.codexBridge.decode(type, from: trimmed)
    }
}
