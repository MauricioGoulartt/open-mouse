import Foundation

public struct ReleaseVersion: Equatable, Comparable {
    public let numbers: [Int]
    public let prerelease: [String]
    public init?(_ text: String) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        guard value.utf8.count < 128 else { return nil }
        let withoutBuild = value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let parts = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numeric = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numeric.count == 3 else { return nil }
        var result: [Int] = []
        for number in numeric {
            guard !number.isEmpty, number.allSatisfy({ $0.isASCII && $0.isNumber }),
                  number.count == 1 || number.first != "0", let parsed = Int(number) else { return nil }
            result.append(parsed)
        }
        var suffix: [String] = []
        if parts.count == 2 {
            suffix = parts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard suffix.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } }) else { return nil }
            guard suffix.allSatisfy({ Int($0) == nil || $0.count == 1 || !$0.hasPrefix("0") }) else { return nil }
        }
        self.numbers = result; self.prerelease = suffix
    }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.numbers != rhs.numbers { return lhs.numbers.lexicographicallyPrecedes(rhs.numbers) }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }
        for (a, b) in zip(lhs.prerelease, rhs.prerelease) where a != b {
            if let x = Int(a), let y = Int(b) { return x < y }
            if Int(a) != nil { return true }
            if Int(b) != nil { return false }
            return a < b
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}
