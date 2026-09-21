import Foundation

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
}

enum AppCopy {
    static let welcomeTitle = "ふたりの「当たり前」を、\nわが家の約束に。"
    static let welcomeBody = "家で大切にしたいことを一緒に決めて、\nときどき振り返るためのアプリです。"
    static let start = "はじめる"
    static let yourName = "あなたの呼び名"
    static let startTogetherTitle = "ふたりではじめる"
    static let startTogetherBody = "パートナーを招待して、\n一緒にはじめましょう。"
    static let homeHeader = "わが家"
    static let weekUsualTitle = "今日も、いつもどおり。"
    static let weekUsualBody = "気になったことや、うれしかったことがあったら残しておきましょう。"
    static let weekReviewTitle = "ふりかえってみませんか？"
    static let weekReviewBody = "約束のことと、日々の想いを見てみましょう。"
    static let weekReviewAction = "ふりかえる"
    static let agreements = "わが家の約束"
    static let addToday = "＋  今日のことを残す"
    static let whatAgreement = "どんな約束にする？"
    static let whoApplies = "この約束が当てはまるのは？"
    static let addMemo = "＋ メモを追加"
    static let saveAgreement = "この約束を追加する"
    static let saveChanges = "変更を保存する"
    static let edit = "編集する"
    static let delete = "削除する"
    static let deleteAgreementTitle = "この約束を削除しますか？"
    static let deleteAgreementBody = "これまでの振り返りの記録は残ります。"
    static let deleteConfirm = "削除する"
    static let cancel = "やめる"
    static let whichAgreement = "どの約束について？"
    static let whatHappened = "どんなことがあった？"
    static let aWordTitle = "よかったら、ひとこと"
    static let aWordBody = "あとでふたりで振り返るときに分かるくらいで大丈夫です。"
    static let keepRecord = "残しておく"
    static let thisWeek = "今週のこと"
    static let applicableAsk = "いま、自分はこの約束はまもれているかな？"
    static let partnerAskSuffix = "は、この約束をまもれてた？"
    static let notThisWeek = "今回はなかった"
    static let partnerFelt = "今週、相手が感じたこと"
    static let reviewDoneTitle = "今週のふりかえりはここまでです。"
    static let reviewDoneBody = "気になることがあれば、ふたりで話してみましょう。"
    static let finish = "おわる"
    static let untilNow = "これまで"
    static let both = "ふたりとも"
    static let conditional = "そのとき当てはまる人"
    static let partner = "パートナー"
    static let talkFirst = "ふたりで話して決めた内容を残しておきましょう。"
    static let weeklyNoticeTitle = "ふりかえる時間です。"
    static let weeklyNoticeBody = "少しだけ、いまのことを見てみませんか？"
    static let bothReadyTitle = "ふたりの振り返りがそろいました。"
    static let bothReadyBody = "今週感じたことを一緒に見てみましょう。"
}
