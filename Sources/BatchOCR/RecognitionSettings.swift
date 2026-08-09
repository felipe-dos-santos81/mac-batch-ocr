import Foundation

struct RecognitionSettings: Sendable {
    var languages: [String] = ["en"]
    var usesLanguageCorrection = false
    var automaticallyDetectsLanguage = false
}
