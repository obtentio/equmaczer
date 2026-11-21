import Combine

@MainActor
final class RecordingController: ObservableObject {
    @Published var isMacMuted = false
    @Published private(set) var configuration = RecordingConfiguration()
    @Published private(set) var notice: String?
    @Published private(set) var requestingPermission = false
    var onChange: ((RecordingConfiguration) -> Void)?
    private let permission: any PermissionRequesting
    private var permissionGeneration = 0

    init(permission: any PermissionRequesting = AudioPermissionService()) { self.permission = permission }

    func updateEnabled(_ enabled: Bool) {
        permissionGeneration += 1
        configuration.enabled = enabled
        onChange?(configuration)
    }

    func updateIncludeMic(_ enabled: Bool) async {
        permissionGeneration += 1
        let stamp = permissionGeneration
        if enabled {
            guard configuration.enabled else { return }
            requestingPermission = true
            let granted = permission.isMicPermissionGranted ? true : await permission.requestMicPermission()
            requestingPermission = false
            guard stamp == permissionGeneration, configuration.enabled else { return }
            guard granted else {
                configuration.includeMic = false
                notice = "Allow equmaczer under Microphone in Privacy & Security."
                onChange?(configuration)
                return
            }
        }
        notice = nil
        configuration.includeMic = enabled
        onChange?(configuration)
    }

    func updateMicrophone(_ uid: String?) {
        configuration.microphoneUID = uid
        onChange?(configuration)
    }

    func restore(_ snapshot: AppStateSnapshot) {
        configuration = RecordingConfiguration(enabled: snapshot.recordingEnabled,
            includeMic: snapshot.recordingIncludeMic && permission.isMicPermissionGranted,
            microphoneUID: snapshot.recordingMicrophoneUID)
        if snapshot.recordingIncludeMic && !permission.isMicPermissionGranted {
            notice = "Allow equmaczer under Microphone in Privacy & Security."
        }
        onChange?(configuration)
    }
}
