import Foundation
import Supabase

enum SupabaseConfig {
    /// プロジェクトのルート URL（末尾の /rest/v1 は不要）
    static let urlString = "https://rlzjskovfcvnljaresoz.supabase.co"
    /// API Keys の anon / publishable キー
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJsempza292ZmN2bmxqYXJlc296Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAwMDQzMjUsImV4cCI6MjEwNTU4MDMyNX0.PPuyPPLJDmhS1TmbPbd0kycr_E-5wtlqImTDNdAQe0o"

    static var isConfigured: Bool {
        projectURL != nil && anonKey.count > 20
    }

    static var projectURL: URL? {
        var raw = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in ["/rest/v1/", "/rest/v1", "/"] where raw.lowercased().hasSuffix(suffix) {
            raw.removeLast(suffix.count)
        }
        guard raw.hasPrefix("https://"), let url = URL(string: raw) else { return nil }
        return url
    }

    static func client() throws -> SupabaseClient {
        if let cached = cachedClient {
            return cached
        }
        guard isConfigured, let url = projectURL else {
            throw AppError.notConfigured
        }
        let client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(
                db: .init(encoder: makeEncoder(), decoder: makeDecoder())
            )
        )
        cachedClient = client
        return client
    }

    private static var cachedClient: SupabaseClient?

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(TimestampCoding.string(from: date))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let raw = try? container.decode(String.self),
               let date = TimestampCoding.date(from: raw) {
                return date
            }
            if let interval = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: interval)
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date"
            )
        }
        return decoder
    }
}

enum TimestampCoding {
    static func date(from raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withT = trimmed.contains("T")
            ? trimmed
            : trimmed.replacingOccurrences(of: " ", with: "T")
        if let date = parseISO(withT) {
            return date
        }
        if let date = parseISO(ensureTimeZone(withT)) {
            return date
        }
        if let year = Int(trimmed.prefix(4)),
           trimmed.count >= 10,
           trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)] == "-",
           let month = Int(trimmed.dropFirst(5).prefix(2)),
           let day = Int(trimmed.dropFirst(8).prefix(2)) {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            return AppWeek.calendar.date(from: components)
        }
        return nil
    }

    static func string(from date: Date) -> String {
        isoFormatter(withFraction: true).string(from: date)
    }

    private static func parseISO(_ raw: String) -> Date? {
        let normalized = normalizeFractionalSeconds(raw)
        return isoFormatter(withFraction: true).date(from: normalized)
            ?? isoFormatter(withFraction: false).date(from: raw)
            ?? isoFormatter(withFraction: false).date(from: normalized)
    }

    private static func ensureTimeZone(_ raw: String) -> String {
        if raw.hasSuffix("Z") { return raw }
        if raw.range(of: #"[+-]\d{2}(:?\d{2})?$"#, options: .regularExpression) != nil {
            return raw
        }
        guard raw.contains("T") else { return raw }
        return raw + "Z"
    }

    private static func isoFormatter(withFraction: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = withFraction
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    /// Postgres often emits 6-digit microseconds. ISO8601DateFormatter wants 3.
    private static func normalizeFractionalSeconds(_ raw: String) -> String {
        guard let dot = raw.firstIndex(of: ".") else { return raw }
        let fractionStart = raw.index(after: dot)
        var index = fractionStart
        var digits = 0
        while index < raw.endIndex, raw[index].isNumber {
            digits += 1
            index = raw.index(after: index)
        }
        guard digits > 0 else { return raw }
        let fraction = String(raw[fractionStart..<index])
        let millis = String((fraction + "000").prefix(3))
        return String(raw[raw.startIndex..<fractionStart]) + millis + String(raw[index...])
    }
}
