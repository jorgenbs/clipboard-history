import Foundation

public enum ClipSearch {
    /// Case-insensitive substring match. Text clips match on their text; image clips match on
    /// "img"/"image" and on the source app name.
    public static func filter(_ clips: [Clip], query: String) -> [Clip] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return clips }
        return clips.filter { matches($0, query: q) }
    }

    public static func matches(_ clip: Clip, query: String) -> Bool {
        if clip.kind == .image {
            if "img".range(of: query, options: [.caseInsensitive, .anchored]) != nil { return true }
            if "image".range(of: query, options: [.caseInsensitive, .anchored]) != nil { return true }
            return clip.sourceAppName?.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        return clip.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

public enum RelativeTime {
    /// "now", "3m", "2h", "Yesterday", "4d", then a short date.
    public static func string(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if calendar.isDate(date, inSameDayAs: now) { return "\(Int(seconds / 3600))h" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days < 7 { return "\(days)d" }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.setLocalizedDateFormatFromTemplate(calendar.isDate(date, equalTo: now, toGranularity: .year) ? "MMMd" : "yMMMd")
        return f.string(from: date)
    }
}
