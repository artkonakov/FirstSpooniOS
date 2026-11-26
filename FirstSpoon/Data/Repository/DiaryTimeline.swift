import FirstSpoonCore

enum DiaryTimelineItem: Identifiable {
    case product(DiaryEntry)
    case meal(RecipeMeal)

    var id: String {
        switch self {
        case .product(let item): return "trial-\(item.id)"
        case .meal(let item): return "meal-\(item.id)"
        }
    }

    var date: LocalDate {
        switch self {
        case .product(let item): return item.date
        case .meal(let item): return item.date
        }
    }

    var time: LocalTime? {
        switch self {
        case .product(let item): return item.time
        case .meal(let item): return item.time
        }
    }

    var createdAt: Int64 {
        switch self {
        case .product(let item): return item.createdAt
        case .meal(let item): return item.createdAt
        }
    }

    static func newestFirst(entries: [DiaryEntry], meals: [RecipeMeal]) -> [Self] {
        (entries.map(Self.product) + meals.map(Self.meal)).sorted { left, right in
            if left.date != right.date { return left.date > right.date }
            let first = left.time?.minuteOfDay ?? -1
            let second = right.time?.minuteOfDay ?? -1
            if first != second { return first > second }
            return left.createdAt > right.createdAt
        }
    }
}
