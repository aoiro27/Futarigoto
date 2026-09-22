import Foundation

enum ObservationPhotoPolicy {
    static let lifetime: TimeInterval = 10 * 24 * 60 * 60

    static func expiryDate(from date: Date = .now) -> Date {
        date.addingTimeInterval(lifetime)
    }
}

enum ScopeType: String, Codable, CaseIterable, Identifiable {
    case both = "BOTH"
    case conditional = "CONDITIONAL"
    case specificUser = "SPECIFIC_USER"

    var id: String { rawValue }
}

enum ObservationType: String, Codable, CaseIterable, Identifiable {
    case positive = "POSITIVE"
    case concern = "CONCERN"
    case other = "OTHER"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .positive: "うれしかった"
        case .concern: "気になった"
        case .other: "その他"
        }
    }

    var symbol: String {
        switch self {
        case .positive: "😊"
        case .concern: "😕"
        case .other: "💬"
        }
    }

    var display: String {
        "\(symbol) \(label)"
    }
}

enum SelfReflection: String, Codable, CaseIterable, Identifiable {
    case veryGood = "VERY_GOOD"
    case mostlyGood = "MOSTLY_GOOD"
    case sometimesMissed = "SOMETIMES_MISSED"
    case oftenMissed = "OFTEN_MISSED"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .veryGood: "まもれたと思う"
        case .mostlyGood: "だいたいまもれた"
        case .sometimesMissed: "まもれないこともあった"
        case .oftenMissed: "あまりまもれなかった"
        }
    }

    var rank: Int {
        switch self {
        case .veryGood: 3
        case .mostlyGood: 2
        case .sometimesMissed: 1
        case .oftenMissed: 0
        }
    }
}

enum AppCopy {
    static let welcomeTitle = "ふたりごと"
    static let welcomeBody = "家の約束を決めて、ときどきふりかえる。"
    static let start = "はじめる"
    static let yourName = "呼び名"
    static let startTogetherTitle = "招待"
    static let homeHeader = "わが家"
    static let weekReviewTitle = "ふりかえり"
    static let weekReviewAction = "はじめる"
    static let agreements = "わが家の約束"
    static let addToday = "追加"
    static let whatAgreement = "約束"
    static let whoApplies = "だれの約束？"
    static let addMemo = "メモを追加"
    static let saveAgreement = "追加する"
    static let saveChanges = "保存する"
    static let edit = "編集"
    static let delete = "削除"
    static let deleteAgreementTitle = "この約束を削除しますか？"
    static let deleteAgreementBody = "これまでのふりかえりは残ります。"
    static let deleteConfirm = "削除する"
    static let cancel = "やめる"
    static let whichAgreement = "どの約束？"
    static let whatHappened = "なにがあった？"
    static let aWordTitle = "ひとこと"
    static let addPhoto = "写真を添える"
    static let changePhoto = "写真を変える"
    static let removePhoto = "写真をはずす"
    static let photoLibrary = "ライブラリ"
    static let takePhoto = "カメラ"
    static let photoLoadFailedTitle = "写真を読み込めませんでした"
    static let photoLoadFailedBody = "別の写真を選ぶか、もう一度試してください。"
    static let keepRecord = "残す"
    static let thisWeek = "今週"
    static let applicableAsk = "自分は、まもれてた？"
    static let partnerAskSuffix = "は、まもれてた？"
    static let notThisWeek = "今回はなかった"
    static let selfEvalLabel = "自分"
    static let finish = "とじる"
    static let untilNow = "これまで"
    static let both = "ふたりとも"
    static let conditional = "そのとき当てはまる人"
    static let partner = "パートナー"
    static let weeklyNoticeTitle = "ふりかえりの時間です"
    static let weeklyNoticeBody = "今日のふりかえりができます。"
    static let bothReadyTitle = "ふりかえりがそろいました"
    static let bothReadyBody = "結果を見られます。"
}
