import CoreAudio

/// Transport policy evaluated on the control side before callbacks start.
enum OutputLimiterCeiling {
    static func dbTP(for device: AudioDevice?) -> Float {
        device?.isBluetooth == true
            ? AudioConstants.bluetoothLimiterCeilingDBTP
            : AudioConstants.limiterCeilingDBTP
    }
}
