import Foundation

/// A monetary amount stored in the currency's minor units (for example, cents).
/// This deliberately avoids binary floating-point values for financial data.
public struct Money: Codable, Hashable, Sendable {
    public let minorUnits: Int64
    public let currencyCode: String

    public init(minorUnits: Int64, currencyCode: String = "USD") {
        self.minorUnits = minorUnits
        self.currencyCode = currencyCode.uppercased()
    }

    public static func zero(currencyCode: String = "USD") -> Money {
        Money(minorUnits: 0, currencyCode: currencyCode)
    }
}

public enum MoneyConversion {
    public static func minorUnits(from decimal: Decimal, scale: Int = 2) throws -> Int64 {
        guard scale >= 0 else { throw BankingError.invalidConfiguration("Money scale cannot be negative") }
        var multiplier = Decimal(1)
        for _ in 0..<scale { multiplier *= 10 }
        var scaled = decimal * multiplier
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .bankers)
        let number = NSDecimalNumber(decimal: rounded)
        guard number != .notANumber else { throw BankingError.malformedTransaction("Amount is not a number") }
        let value = number.int64Value
        guard Decimal(value) == rounded else {
            throw BankingError.malformedTransaction("Amount is outside Int64 range")
        }
        return value
    }
}
