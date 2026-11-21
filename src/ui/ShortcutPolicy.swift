import AppKit

/// Caps Lock and keyboard-layout flags are not command modifiers.
enum ShortcutPolicy {
    static func isUnmodified(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection([.command, .control, .option, .shift]).isEmpty
    }
}
