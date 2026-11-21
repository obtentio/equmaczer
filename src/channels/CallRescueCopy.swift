/// One home for call-rescue wording on both remote surfaces.
enum CallRescueCopy {
    static func title(headset: String) -> String { "\(headset) on call quality ·" }
    static func dropped(headset: String) -> String { "\(headset) dropped to call quality." }
    static func use(microphone: String) -> String { "Use \(microphone)" }
    static let stereo = "for this call to get stereo back."
    static func noMicrophone(headset: String) -> String {
        "\(dropped(headset: headset)) Plug in a mic to get stereo back."
    }
    static func restore(microphone: String) -> String { "Restore \(microphone)" }
}
