import Foundation

/// All page indices are zero-based internally; the UI displays one-based numbers.
struct PageNavigation {
    static func clampedIndex(_ proposed: Int, pageCount: Int) -> Int {
        min(max(proposed, 0), max(pageCount - 1, 0))
    }

    static func index(forPageNumber text: String, pageCount: Int) -> Int? {
        guard let number = Int(text), number >= 1, number <= pageCount else { return nil }
        return number - 1
    }
}
