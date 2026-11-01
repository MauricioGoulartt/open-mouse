import Foundation

public enum ConfigurationFile {
    public static func encode(_ configuration: Configuration) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(configuration.validated())
    }
    public static func decode(_ data: Data) throws -> Configuration {
        guard data.count <= 2_000_000 else { throw ConfigurationError.invalidValue }
        return try JSONDecoder().decode(Configuration.self, from: data).validated()
    }
    public static func save(_ configuration: Configuration, to url: URL) throws {
        let data = try encode(configuration)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
