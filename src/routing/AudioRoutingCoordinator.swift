// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
// AudioRoutingCoordinator.swift
// Coordinates audio routing: device selection and pipeline management

import Combine
import CoreAudio
import Foundation
import OSLog

/// Coordinates audio routing between input and output devices.
/// Manages the RenderPipeline and handles device selection, sample rate sync,
/// and mode switching (automatic vs manual).
@MainActor
final class AudioRoutingCoordinator: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var routingStatus: RoutingStatus = .idle
    @Published var selectedInputDeviceID: String?
    @Published var selectedOutputDeviceID: String?
    @Published var manualModeEnabled: Bool = false {
        didSet {
            routingMode = manualModeEnabled ? ManualRoutingMode() as RoutingMode : AutomaticRoutingMode() as RoutingMode
            // Mode switch changes the effective capture mode — new route generation.
            bumpRouteGeneration()
        }
    }
    private(set) var routingMode: RoutingMode = AutomaticRoutingMode()
    @Published var showDriverPrompt: Bool = false
    
    /// Whether the driver needs updating (supports outdated driver detection).
    /// Set when driver doesn't support shared memory capture.
    @Published var showDriverUpdateRequired: Bool = false

    /// Capture mode preference for automatic routing.
    /// In automatic mode with the equmaczer driver, this determines how audio is captured.
    /// Manual mode always uses HAL input capture.
    @Published var captureMode: CaptureMode = CaptureMode.defaultMode

    /// The capture mode currently in use (may differ from preference when driver doesn't support shared memory).
    /// Returns `halInput` when driver doesn't support shared memory or in manual mode.
    var effectiveCaptureMode: CaptureMode {
        if manualModeEnabled { return .halInput }
        if captureMode == .processTap { return .processTap }
        if driverAccess.isReady && !driverAccess.hasSharedMemoryCapability() {
            return .halInput
        }
        return captureMode
    }
    
    // MARK: - Dependencies

    let deviceProvider: DeviceProviding
    let deviceChangeCoordinator: DeviceChangeCoordinator
    private let eqConfiguration: EQConfiguration
    private let meterStore: MeterStore
    private let volumeService: VolumeControlling
    private let permissionService: PermissionRequesting
    private let processTapHardware: ProcessTapHardwareControlling

    // MARK: - Constants

    private enum Constants {
        /// Delay after syncing driver sample rate before creating HAL input unit.
        /// Allows CoreAudio to propagate the rate change.
        static let sampleRatePropagationDelay: TimeInterval = 0.1

        /// Delay between fade-out and pipeline stop.
        /// Allows the audio thread's per-callback gain ramping to fade output
        /// to silence (~10ms per callback) before the HAL unit is stopped.
        static let fadeOutDuration: TimeInterval = 0.05
    }
    private let systemDefaultObserver: SystemDefaultObserver
    private let sampleRateService: SampleRateObserving
    let driverAccess: DriverAccessing
    private let driverNameManager: DriverNameManager

    // MARK: - Private Types

    /// Holds resolved device information from device resolution and ID lookup.
    private struct ResolvedDevices {
        let inputUID: String
        let outputUID: String
        let inputDeviceID: AudioDeviceID
        let outputDeviceID: AudioDeviceID
        let outputDevice: AudioDevice
    }

    // MARK: - Private Properties

    let pipelineManager: PipelineManager
    private var observedOutputDeviceID: AudioDeviceID?

    /// The numeric device IDs of the running configuration, cached
    /// at start so the health panel can read live device rates
    /// (B3). Cleared on stop.
    private var activeInputDeviceID: AudioDeviceID?
    private var activeOutputDeviceID: AudioDeviceID?
    private var isReconfiguring = false
    private var cancellables = Set<AnyCancellable>()
    let eqStager: EQCoefficientStager

    /// Correction layer owner, wired by `EqumaczerStore` after both
    /// objects exist. Reapplies its layer whenever the configuration
    /// is reapplied (pipeline starts recreate the render chains).
    weak var correctionController: CorrectionController?
    private(set) var channelTapAssignments: [ChannelTapAssignment] = []
    private var tapRestartScheduled = false

    /// One route event per changed process set. Rapid changes publish the
    /// latest set immediately and collapse into one restart on the main queue.
    func updateChannelTapAssignments(_ assignments: [ChannelTapAssignment]) {
        let canonical = AudioChannel.allCases.compactMap { channel -> ChannelTapAssignment? in
            let ids = Set(assignments.filter { $0.bundleID == nil && $0.channel == channel }.flatMap(\.objectIDs))
            return ids.isEmpty ? nil : ChannelTapAssignment(channel: channel, objectIDs: ids.sorted())
        }.sorted { $0.channel.rawValue < $1.channel.rawValue } + assignments.filter { $0.bundleID != nil }.map {
            ChannelTapAssignment(channel: $0.channel, objectIDs: Array(Set($0.objectIDs)).sorted(), bundleID: $0.bundleID, skipEQ: $0.skipEQ, treatsChannel: $0.treatsChannel)
        }.sorted { $0.bundleID! < $1.bundleID! }
        guard canonical != channelTapAssignments else { return }
        channelTapAssignments = canonical
        bumpRouteGeneration()
        guard pipelineManager.renderPipeline?.activeCaptureMode == .processTap,
              !tapRestartScheduled else { return }
        tapRestartScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tapRestartScheduled = false
            guard !self.isStopping, self.pipelineManager.renderPipeline?.activeCaptureMode == .processTap else { return }
            self.reconfigureRouting()
        }
    }

    private(set) var recordingConfiguration = RecordingConfiguration()

    func updateRecordingConfiguration(_ configuration: RecordingConfiguration) {
        guard configuration != recordingConfiguration else { return }
        recordingConfiguration = configuration
        pipelineManager.renderPipeline?.updateRecordingFeed(enabled: configuration.enabled, includeMic: configuration.includeMic)
        bumpRouteGeneration()
        guard pipelineManager.renderPipeline?.activeCaptureMode == .processTap else { return }
        reconfigureRouting()
    }

    weak var channelController: ChannelController?
    weak var hearingController: HearingController?

    /// Notice for the status bar when the capture liveness watchdog
    /// moved routing to a fallback route, or gave up. Cleared on the
    /// next fresh reconfigure.
    @Published var captureFallbackNotice: String?

    /// Capture routes that started but produced no audio in this
    /// routing session. Reset on every fresh (non-retry) reconfigure,
    /// which bounds watchdog retries: Process Tap gets one rebuild,
    /// then every failed route is excluded so fallback can never loop.
    private var captureRetryState = CaptureRetryState()
    /// Process Tap heard nothing this session (usually the capture permission).
    var processTapFailed: Bool { captureRetryState.failedCaptureModes.contains(.processTap) }
    private var captureModeOverride: CaptureMode?
    private var isCaptureFallbackRetry = false

    /// The capture route actually running (the preference, an
    /// override, or a watchdog fallback) — published so the Driver
    /// pane can show reality next to the preference (B1).
    @Published private(set) var currentCaptureMode: CaptureMode?

    /// The committed route (S3): the tuple the running pipeline was
    /// proven to implement — the read-back this coordinator captured at
    /// the last successful start. Cleared on teardown; compared by the
    /// quiescent commit against the settled state before restarting.
    private var committedTuple: RouteSeam.RouteTuple?

    /// Whether the upcoming reconfigure is commit-driven (a quiescent
    /// commit that recoalesced after a read-back mismatch): a second
    /// mismatch must not schedule a third restart from the same decision.
    private var isQuiescentCommitReconfigure = false

    /// Monotonically increasing generation counter. Every event that
    /// changes what "the current route" means — output device change,
    /// nominal sample-rate change, capture-mode change, wake, or
    /// watchdog-triggered retry — increments it. Async work captures
    /// the generation it was started under and revalidates before acting.
    /// Internal (not private) so tests can drive generation scenarios.
    var routeGeneration: UInt64 {
        seam.generation
    }
    private var livenessTask: Task<Void, Never>?

    /// The routing seam: generation, quiescence, read-back, and liveness
    /// verdict logic in a pure, testable value type.
    private var seam = RouteSeam()

    /// Monitors for detecting when active routing devices are removed.
    /// Provides faster, more reliable disconnect detection than the full device list diff.
    private var inputDeviceAliveMonitor: DeviceAliveMonitor?
    private var outputDeviceAliveMonitor: DeviceAliveMonitor?

    private let logger = Logger(subsystem: "com.obtentio.equmaczer", category: "AudioRoutingCoordinator")
    
    // MARK: - Initialization
    
    init(
        deviceProvider: DeviceProviding,
        deviceChangeCoordinator: DeviceChangeCoordinator,
        eqConfiguration: EQConfiguration,
        meterStore: MeterStore,
        volumeService: VolumeControlling,
        permissionService: PermissionRequesting,
        systemDefaultObserver: SystemDefaultObserver,
        sampleRateService: SampleRateObserving,
        driverAccess: DriverAccessing? = nil,
        processTapHardware: ProcessTapHardwareControlling = ProcessTapHardwareService()
    ) {
        self.deviceProvider = deviceProvider
        self.deviceChangeCoordinator = deviceChangeCoordinator
        self.eqConfiguration = eqConfiguration
        self.meterStore = meterStore
        self.volumeService = volumeService
        self.permissionService = permissionService
        self.processTapHardware = processTapHardware
        self.systemDefaultObserver = systemDefaultObserver
        self.sampleRateService = sampleRateService
        self.eqStager = EQCoefficientStager(eqConfiguration: eqConfiguration)
        self.pipelineManager = PipelineManager(
            eqConfiguration: eqConfiguration,
            meterStore: meterStore,
            volumeService: volumeService,
            eqStager: eqStager
        )
        
        // Initialize driver access first (needed by driverNameManager)
        let resolvedDriverAccess = driverAccess ?? DriverManager.shared
        self.driverAccess = resolvedDriverAccess
        
        // Create driver name manager for CoreAudio refresh workaround
        self.driverNameManager = DriverNameManager(
            driverAccess: resolvedDriverAccess,
            systemDefaultObserver: systemDefaultObserver,
            deviceProvider: deviceProvider
        )
        
        // Wire up system default callback
        systemDefaultObserver.onSystemDefaultChanged = { [weak self] device in
            self?.handleSystemDefaultChanged(device)
        }
        
        // Wire up device change coordinator callbacks
        deviceChangeCoordinator.onBuiltInDeviceAdded = { [weak self] device in
            self?.handleBuiltInDeviceAdded(device)
        }
        deviceChangeCoordinator.onBuiltInDevicesRemoved = { [weak self] in
            self?.handleBuiltInDevicesRemoved()
        }
        deviceChangeCoordinator.onSelectedOutputMissing = { [weak self] uid in
            self?.handleSelectedOutputMissing(uid)
        }
        deviceChangeCoordinator.onSelectedOutputRestored = { [weak self] uid in
            self?.handleSelectedOutputRestored(uid)
        }
        
        // Set up providers for device change detection
        deviceChangeCoordinator.setProviders(
            selectedOutputProvider: { [weak self] in
                self?.selectedOutputDeviceID
            },
            manualModeProvider: { [weak self] in
                self?.manualModeEnabled ?? false
            },
            isReconfiguringProvider: { [weak self] in
                self?.isReconfiguring ?? false
            }
        )
    }
    
    // MARK: - Public Methods

    /// Reconfigures the audio routing pipeline.
    /// In automatic mode: derives devices from macOS default output.
    /// In manual mode: uses user-selected devices.
    func reconfigureRouting() {
        let modeStr = manualModeEnabled ? "manual" : "automatic"
        logger.debug("reconfigureRouting(mode=\(modeStr))")
        // Increment generation for fresh routing session
        bumpRouteGeneration()
        // An explicit reconfigure supersedes any pending coalesced commit:
        // its timer stays scheduled but will find no window to close.
        seam.cancelWindow()

        // Prevent re-entrant calls
        guard !isReconfiguring else {
            logger.debug("reconfigureRouting: skipped (already reconfiguring)")
            return
        }

        isReconfiguring = true

        // A fresh reconfigure starts a new routing session: the
        // liveness watchdog stops, and previously failed capture
        // routes earn a fresh chance (a device may have changed).
        // Fallback retries skip the reset — their failed set and
        // notice are the state that drives the retry.
        cancelLivenessMonitor()
        if !isCaptureFallbackRetry {
            captureRetryState = CaptureRetryState()
            captureFallbackNotice = nil
        }

        // If pipeline is running, fade out before stopping to prevent audio pop.
        // The fade ramps gains to zero over ~10ms; we wait 50ms for it to complete.
        if pipelineManager.renderPipeline != nil {
            pipelineManager.prepareForStop()
            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.fadeOutDuration) { [weak self] in
                self?.continueReconfigureRouting()
            }
        } else {
            continueReconfigureRouting()
        }
    }

    /// Continues routing configuration after the fade-out delay.
    /// Separated from reconfigureRouting() to allow the fade-out to complete.
    private func continueReconfigureRouting() {
        // Step 1: Verify permissions (HAL input requires microphone permission)
        guard validatePermissions() else {
            isReconfiguring = false
            return
        }

        // Stop existing pipeline if running (after fade-out completes)
        stopPipeline()

        // Step 2: Verify driver is ready (automatic mode)
        guard ensureDriverReady() else {
            isReconfiguring = false
            return
        }

        // Step 3: Resolve and validate devices
        guard let devices = resolveAndValidateDevices() else {
            isReconfiguring = false
            return
        }

        // Automatic mode: update selected devices and pre-sync volume
        if !routingMode.isManual {
            selectedInputDeviceID = devices.inputUID
            selectedOutputDeviceID = devices.outputUID

            // Pre-sync driver volume BEFORE updateDriverName() to prevent macOS volume sync
            // from overwriting the new output device's volume.
            if let outputDeviceID = deviceProvider.deviceID(forUID: devices.outputUID),
               let driverID = driverAccess.deviceID,
               let volume = volumeService.getDeviceVolumeScalar(deviceID: outputDeviceID) {
                _ = volumeService.setDeviceVolumeScalar(deviceID: driverID, volume: volume)
                logger.info("Pre-synced driver volume to: \(volume)")
            }

            // Rename driver to match output device
            _ = updateDriverName()

            // Set driver as macOS default IMMEDIATELY (before pipeline starts)
            systemDefaultObserver.setDriverAsDefault(
                onSuccess: { [weak self] in
                    self?.logger.info("Automatic mode: set driver as system default output")
                },
                onFailure: { [weak self] in
                    self?.routingStatus = .error("Failed to set system default output device")
                    self?.logger.error("Automatic mode: failed to set driver as system default")
                    self?.driverAccess.restoreToBuiltInSpeakers()
                }
            )
        }

        // Sync driver sample rate to match output device (automatic mode only)
        if routingMode.requiresSampleRateSync {
            syncDriverSampleRate(to: devices.outputDeviceID)
        }

        // Set up listener for output device sample rate changes
        setupSampleRateListener(for: devices.outputDeviceID)

        // Determine capture mode early - needed to decide if we need rate sync delay
        // A one-shot override from the liveness watchdog takes
        // precedence over the stored preference for this attempt.
        let capturePreference: CaptureMode = captureModeOverride ?? (routingMode.isManual ? .halInput : self.captureMode)
        captureModeOverride = nil
        let supportsSharedMemory = driverAccess.hasSharedMemoryCapability()
        let captureDecision = CaptureModePolicy.determineMode(
            preference: capturePreference,
            isManualMode: routingMode.isManual,
            supportsSharedMemory: supportsSharedMemory
        )
        let resolvedCaptureMode: CaptureMode
        switch captureDecision {
        case .useMode(let mode):
            resolvedCaptureMode = mode
        case .fallbackToHALInput:
            resolvedCaptureMode = .halInput
        }

        // For HAL input mode in automatic mode, add delay after sample rate sync
        // to allow CoreAudio to propagate the rate change before creating input HAL unit.
        // In shared memory mode, no input HAL unit is created, so no delay needed.
        let needsRateSyncDelay = !routingMode.isManual && resolvedCaptureMode == .halInput

        if needsRateSyncDelay {
            // Delay to allow CoreAudio to propagate sample rate change
            logger.debug("Waiting for driver sample rate propagation before HAL input configuration")
            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.sampleRatePropagationDelay) { [weak self] in
                self?.isReconfiguring = false
                self?.continueRoutingConfiguration(
                    inputDeviceID: devices.inputDeviceID,
                    outputDeviceID: devices.outputDeviceID,
                    outputDevice: devices.outputDevice,
                    inputUID: devices.inputUID,
                    outputUID: devices.outputUID,
                    resolvedCaptureMode: resolvedCaptureMode,
                    captureDecision: captureDecision
                )
            }
        } else {
            isReconfiguring = false
            continueRoutingConfiguration(
                inputDeviceID: devices.inputDeviceID,
                outputDeviceID: devices.outputDeviceID,
                outputDevice: devices.outputDevice,
                inputUID: devices.inputUID,
                outputUID: devices.outputUID,
                resolvedCaptureMode: resolvedCaptureMode,
                captureDecision: captureDecision
            )
        }
    }

    // MARK: - Routing Step Methods

    /// Validates that microphone permission is granted when HAL input capture is required.
    /// Returns true if routing should proceed, false if blocked (permission request issued).
    private func validatePermissions() -> Bool {
        let needsPermission = routingMode.needsMicPermission || (!routingMode.isManual && captureMode == .halInput)
        guard needsPermission else { return true }

        guard permissionService.isMicPermissionGranted else {
            requestPermissionAndRetryRouting()
            return false
        }

        // Permission is granted, but input devices may not be enumerated yet
        // (permission persists across sessions, but device enumeration doesn't)
        if routingMode.isManual && deviceProvider.inputDevices.isEmpty {
            logger.info("Permission granted but input devices not enumerated - enumerating now")
            deviceProvider.enumerateInputDevices()
        }

        return true
    }

    /// Ensures the driver is installed and visible (automatic mode prerequisite).
    /// Returns true if routing should proceed, false if blocked (driver not ready or retry issued).
    private func ensureDriverReady() -> Bool {
        guard routingMode.requiresDriverVisibility else { return true }

        guard driverAccess.isReady else {
            routingStatus = .driverNotInstalled
            logger.warning("Routing cannot start: driver not installed")
            showDriverPrompt = true
            return false
        }

        guard driverAccess.isDriverVisible() else {
            ensureDriverVisible { [weak self] in
                self?.reconfigureRouting()
            }
            return false
        }

        return true
    }

    /// Resolves devices using the routing mode strategy and validates device IDs.
    /// Returns resolved devices on success, nil on failure (routingStatus already set).
    private func resolveAndValidateDevices() -> ResolvedDevices? {
        // Resolve devices using the routing mode strategy
        let resolution = routingMode.resolveDevices(
            selectedInputDeviceID: selectedInputDeviceID,
            selectedOutputDeviceID: selectedOutputDeviceID,
            deviceProvider: deviceProvider,
            systemDefaultObserver: systemDefaultObserver,
            driverAccess: driverAccess,
            captureMode: captureMode
        )

        let inputUID: String
        let outputUID: String

        switch resolution {
        case .resolved(let resolvedInput, let resolvedOutput):
            inputUID = resolvedInput
            outputUID = resolvedOutput
        case .failed(let message):
            routingStatus = .error(message)
            logger.error("Device resolution failed: \(message)")
            return nil
        }

        // For automatic mode, ensure driver is still visible before proceeding
        if routingMode.requiresDriverVisibility && inputUID == DRIVER_DEVICE_UID {
            if !driverAccess.isDriverVisible() {
                ensureDriverVisible { [weak self] in
                    self?.reconfigureRouting()
                }
                return nil
            }
        }

        // Resolve device IDs with diagnostic logging
        let inputDeviceID = deviceProvider.deviceID(forUID: inputUID)
        let outputDeviceID = deviceProvider.deviceID(forUID: outputUID)
        let outputDevice = deviceProvider.device(forUID: outputUID)

        if inputDeviceID == nil {
            logger.error("Failed to resolve input device ID for UID: \(inputUID)")
        }
        if outputDeviceID == nil {
            logger.error("Failed to resolve output device ID for UID: \(outputUID)")
        }
        if outputDevice == nil {
            logger.error("Failed to resolve output device for UID: \(outputUID)")
        }

        guard let inputDeviceID = inputDeviceID,
              let outputDeviceID = outputDeviceID,
              let outputDevice = outputDevice else {
            routingStatus = .error("Failed to resolve device IDs")
            logger.error("Failed to resolve device IDs")
            return nil
        }

        logger.debug("Device IDs resolved: input=\(inputDeviceID), output=\(outputDeviceID)")

        return ResolvedDevices(
            inputUID: inputUID,
            outputUID: outputUID,
            inputDeviceID: inputDeviceID,
            outputDeviceID: outputDeviceID,
            outputDevice: outputDevice
        )
    }

    /// Continues routing configuration after optional rate sync delay.
    /// Separated to allow async delay for HAL input mode.
    private func continueRoutingConfiguration(
        inputDeviceID: AudioDeviceID,
        outputDeviceID: AudioDeviceID,
        outputDevice: AudioDevice,
        inputUID: String,
        outputUID: String,
        resolvedCaptureMode: CaptureMode,
        captureDecision: CaptureModeDecision
    ) {

        // Set up jack connection listener on built-in device (Intel Macs: headphone jack detection)
        // Note: Apple Silicon uses device count change detection in DeviceEnumerationService instead
        if !routingMode.isManual {
            if let builtInDevice = deviceProvider.findBuiltInAudioDevice() {
                deviceChangeCoordinator.setupJackConnectionListener(for: builtInDevice.id)
            }
        }

        // Create and configure the render pipeline
        let outputName = outputDevice.name

        // In automatic mode, use the intended driver name (just set via updateDriverName)
        // instead of reading from cached device list which may not have refreshed yet
        let inputName: String
        if routingMode.isManual {
            guard let inputDevice = deviceProvider.device(forUID: inputUID) else {
                routingStatus = .error("Failed to resolve input device")
                logger.error("Manual mode: failed to resolve input device")
                return
            }
            // If input is the driver, use the known name "equmaczer" (cache may be stale after rename)
            if inputUID == DRIVER_DEVICE_UID {
                inputName = "equmaczer"
            } else {
                inputName = inputDevice.name
            }
        } else {
            inputName = "\(outputDevice.name) (equmaczer)"
        }

        routingStatus = .starting
        logger.info("Starting routing: \(inputName) → \(outputName)")

        // Handle capture mode decision (already determined in reconfigureRouting)
        if case .fallbackToHALInput = captureDecision {
            logger.info("Driver does not support shared memory, falling back to HAL input")
            showDriverUpdateRequired = true
        }

        // Clear driver update flag when using shared memory successfully
        if resolvedCaptureMode == .sharedMemory {
            showDriverUpdateRequired = false
        }

        // Validate shared memory capture requirements
        if resolvedCaptureMode == .sharedMemory {
            guard inputUID == DRIVER_DEVICE_UID else {
                routingStatus = .error("Shared memory capture requires equmaczer driver")
                logger.error("Shared memory capture requires driver as input")
                return
            }
            guard driverAccess.isReady else {
                routingStatus = .error("Driver not installed")
                logger.error("Shared memory capture requires driver")
                return
            }
        }

        // HAL input requires microphone permission
        if resolvedCaptureMode == .halInput {
            guard permissionService.isMicPermissionGranted else {
                requestPermissionAndRetryRouting()
                return
            }
        }

        let registry: DriverDeviceRegistry? = resolvedCaptureMode == .sharedMemory ? driverAccess.deviceRegistry : nil

        let result = pipelineManager.startPipeline(
            inputDeviceID: inputDeviceID,
            outputDeviceID: outputDeviceID,
            captureMode: resolvedCaptureMode,
            driverRegistry: registry,
            isAutomaticMode: !routingMode.isManual,
            driverID: driverAccess.deviceID,
            driverOutputDeviceID: outputDeviceID,
            outputDevice: outputDevice,
            channelTapAssignments: resolvedCaptureMode == .processTap ? channelTapAssignments : [],
            recordingConfiguration: resolvedCaptureMode == .processTap ? recordingConfiguration : RecordingConfiguration()
        )

        switch result {
        case .success(let sampleRate):
            // S3: a route is not .active until the committed tuple —
            // (output UID, sample rate, capture mode) — is read back
            // from the HAL and matches intent. A mismatch is not an
            // error: it is a new event (new generation, one recoalesce).
            let intent = RouteSeam.RouteTuple(
                outputUID: outputUID,
                sampleRate: sampleRate,
                captureMode: resolvedCaptureMode
            )
            let readBack = readBackTuple(outputUID: outputUID)
            let wasQuiescentCommit = isQuiescentCommitReconfigure
            isQuiescentCommitReconfigure = false

            guard RouteSeam.matches(intent: intent, readBack: readBack) else {
                if wasQuiescentCommit {
                    // One recoalesce was already spent and the HAL still
                    // returns another route: loop and it never settles.
                    // Stop honestly rather than commit the wrong route.
                    logger.error("Read-back mismatch persists after recoalesce: asked \(intent.outputUID) @ \(Int(intent.sampleRate)) Hz \(intent.captureMode.displayName), HAL has \(readBack?.outputUID ?? "nothing") @ \(Int(readBack?.sampleRate ?? 0)) Hz — stopping")
                    stopRouting()
                    DispatchQueue.main.asyncAfter(deadline: .now() + Constants.fadeOutDuration + 0.05) { [weak self] in
                        self?.routingStatus = .error("Audio route does not match what was asked for — routing stopped")
                    }
                    return
                }
                logger.warning("Read-back mismatch: asked \(intent.outputUID) @ \(Int(intent.sampleRate)) Hz \(intent.captureMode.displayName), HAL has \(readBack?.outputUID ?? "nothing") @ \(Int(readBack?.sampleRate ?? 0)) Hz — coalescing one retry")
                bumpRouteGeneration()
                scheduleQuiescentCommit()
                return
            }

            committedTuple = intent
            activeInputDeviceID = inputDeviceID
            activeOutputDeviceID = outputDeviceID
            routingStatus = .active(inputName: inputName, outputName: outputName)
            logger.info("Routing active: \(inputName) → \(outputName)")

            // Update sample rate for coefficient calculations
            eqStager.setCurrentSampleRate(sampleRate)

            // Start device alive monitors for immediate disconnect detection
            startDeviceAliveMonitors(inputDeviceID: inputDeviceID, outputDeviceID: outputDeviceID)

            // Prove the capture route actually produces audio;
            // a started-but-silent route falls back instead of
            // sitting in the active state.
            currentCaptureMode = resolvedCaptureMode
            // Creation failure changes the effective tap set as well as its
            // requested membership. Scope the liveness proof to that result.
            if !pipelineManager.renderPipeline!.failedMixerChannels.isEmpty { bumpRouteGeneration() }
            channelController?.refresh()
            startLivenessMonitor()

        case .configurationFailed(let error):
            // Do not strand system output on a virtual device with no reader.
            stopRouting()
            routingStatus = .error("Configuration failed: \(error)")
            logger.error("Pipeline configuration failed: \(error)")

        case .startFailed(let error):
            stopRouting()
            routingStatus = .error("Start failed: \(error)")
            logger.error("Pipeline start failed: \(error)")
        }
    }

    /// Requests microphone permission and retries routing.
    /// Called when HAL input capture is needed and microphone permission hasn't been granted.
    private func requestPermissionAndRetryRouting() {
        routingStatus = .starting  // Show loading state while requesting permission

        Task { @MainActor in
            let granted = await permissionService.requestMicPermission()

            if granted {
                logger.info("Microphone permission granted")
                // Enumerate input devices now that we have permission
                deviceProvider.enumerateInputDevices()
                // Retry routing - permission now granted, HAL input will work
                reconfigureRouting()
            } else {
                logger.warning("Microphone permission denied")
                routingStatus = .error("Microphone permission required for audio routing")
            }
        }
    }

    /// Whether a stop is already in progress (used to prevent re-entrant stops).
    /// Set when stopRouting() begins, cleared when continueStopRouting() finishes.
    private var isStopping = false

    /// Stops the current audio routing and restores system defaults (automatic mode only).
    /// Guarded against re-entrant calls — if a stop is already in progress, this is a no-op.
    func stopRouting() {
        // Prevent double-stop when multiple device-removed notifications fire
        // (e.g. both input and output devices disconnect simultaneously, or
        // CoreAudio sends duplicate property change callbacks).
        guard !isStopping else {
            logger.debug("stopRouting ignored — already stopping")
            return
        }
        isStopping = true
        if pipelineManager.renderPipeline?.activeCaptureMode == .processTap { bumpRouteGeneration() }
        cancelLivenessMonitor()
        // Cancel any pending coalesced restart so it cannot resurrect
        // routing after teardown.
        seam.cancelWindow()
        committedTuple = nil
        isQuiescentCommitReconfigure = false
        currentCaptureMode = nil
        activeInputDeviceID = nil
        activeOutputDeviceID = nil
        logger.info("stopRouting called, manualMode=\(self.manualModeEnabled)")

        // Fade out before stopping to prevent audio pop
        if pipelineManager.renderPipeline != nil {
            pipelineManager.prepareForStop()
            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.fadeOutDuration) { [weak self] in
                self?.continueStopRouting()
            }
        } else {
            continueStopRouting()
        }
    }

    /// Continues stopping after the fade-out delay.
    private func continueStopRouting() {
        // Stop the pipeline
        stopPipeline()

        // In automatic mode, restore macOS default
        if !routingMode.isManual {
            // Restore to selected output device
            if let outputUID = selectedOutputDeviceID,
               outputUID != DRIVER_DEVICE_UID {

                let restored = systemDefaultObserver.restoreSystemDefaultOutput(to: outputUID)
                if !restored {
                    logger.warning("Failed to restore output device, using fallback")
                    if let fallback = findFallbackOutputDevice() {
                        systemDefaultObserver.restoreSystemDefaultOutput(to: fallback.uid)
                    } else {
                        driverAccess.restoreToBuiltInSpeakers()
                    }
                }
            } else {
                // No valid output, use fallback
                if let fallback = findFallbackOutputDevice() {
                    systemDefaultObserver.restoreSystemDefaultOutput(to: fallback.uid)
                } else {
                    driverAccess.restoreToBuiltInSpeakers()
                }
            }

            // Rename driver back to "equmaczer"
            _ = updateDriverName()
        }
        // In manual mode, don't modify macOS default

        // Clear loop prevention flag
        systemDefaultObserver.clearAppSettingFlagAfterDelay()

        routingStatus = .idle
        isStopping = false
        logger.info("Routing stopped")
    }
    
    /// Called after driver installation completes successfully.
    /// Starts routing in automatic mode.
    func handleDriverInstalled() {
        showDriverPrompt = false
        logger.info("Driver installed, starting routing")
        reconfigureRouting()
    }
    
    /// Requests microphone permission and switches to HAL capture mode.
    /// Returns true if permission was granted, false otherwise.
    @discardableResult
    func requestMicPermissionAndSwitchToHALCapture() async -> Bool {
        let granted = await permissionService.requestMicPermission()

        if granted {
            deviceProvider.enumerateInputDevices()
            captureMode = .halInput
            // Capture mode changed: invalidate in-flight async work.
            bumpRouteGeneration()
            if !manualModeEnabled && routingStatus != .idle {
                reconfigureRouting()
            }
            logger.info("Microphone permission granted, switched to HAL capture")
        } else {
            logger.warning("Microphone permission denied, staying with shared memory capture")
        }

        return granted
    }

    /// Requests microphone permission and switches to manual mode.
    /// Manual mode uses HAL input capture, which requires microphone permission.
    /// Returns true if permission was granted and mode switched, false otherwise.
    @discardableResult
    func requestMicPermissionAndSwitchToManualMode() async -> Bool {
        let granted = await permissionService.requestMicPermission()

        if granted {
            deviceProvider.enumerateInputDevices()
            switchToManualMode()
            logger.info("Microphone permission granted, switched to manual mode")
        } else {
            logger.warning("Microphone permission denied, manual mode requires microphone access")
        }

        return granted
    }

    /// Switches to manual mode when user declines to install driver.
    func switchToManualMode() {
        showDriverPrompt = false
        manualModeEnabled = true
        deviceChangeCoordinator.clearHistory()

        // Rename driver back to default since it's no longer used in manual mode
        _ = updateDriverName()

        // Reset driver volume to 100% for clean state when returning to automatic mode
        if let driverID = driverAccess.deviceID {
            volumeService.setDeviceVolumeScalar(deviceID: driverID, volume: 1.0)
        }

        logger.info("Switched to manual mode")

        // Attempt routing if both input and output devices are selected
        if selectedInputDeviceID != nil && selectedOutputDeviceID != nil {
            reconfigureRouting()
        }
    }
    
    /// Switches to automatic mode from manual mode.
    /// Shows driver and starts routing.
    func switchToAutomaticMode() {
        guard driverAccess.isReady else {
            logger.warning("Cannot switch to automatic mode: driver not installed")
            return
        }

        manualModeEnabled = false
        logger.info("Switched to automatic mode")

        // Start routing (this will rename the driver)
        reconfigureRouting()
    }
    
    /// Updates the processing mode on the render pipeline.
    func updateProcessingMode(systemEQOff: Bool, compareMode: CompareMode) {
        pipelineManager.updateProcessingMode(systemEQOff: systemEQOff, compareMode: compareMode)
    }

    /// Updates the input gain on the render pipeline.
    func updateInputGain(linear: Float) {
        pipelineManager.updateInputGain(linear: linear)
    }

    /// Updates the output gain on the render pipeline.
    func updateOutputGain(linear: Float) {
        pipelineManager.updateOutputGain(linear: linear)
    }

    // MARK: - EQ Coefficient Staging (delegated to EQCoefficientStager)

    /// Updates a band's gain by recalculating and staging coefficients.
    func updateBandGain(index: Int) {
        eqStager.updateBandGain(index: index)
    }

    /// Updates a band's Q factor by recalculating and staging coefficients.
    func updateBandQ(index: Int) {
        eqStager.updateBandQ(index: index)
    }

    /// Updates a band's frequency by recalculating and staging coefficients.
    func updateBandFrequency(index: Int) {
        eqStager.updateBandFrequency(index: index)
    }

    /// Updates a band's filter type by recalculating and staging coefficients.
    func updateBandFilterType(index: Int) {
        eqStager.updateBandFilterType(index: index)
    }

    /// Updates a band's bypass state.
    func updateBandBypass(index: Int) {
        eqStager.updateBandBypass(index: index)
    }

    /// Returns the current band capacity from EQConfiguration.
    func currentBandCapacity() -> Int {
        eqStager.currentBandCapacity()
    }

    /// Reapplies all coefficients from the current configuration.
    func reapplyConfiguration() {
        eqStager.reapplyConfiguration()
        correctionController?.refresh()
        channelController?.refresh()
        hearingController?.refresh()
    }

    // MARK: - Health (B3)

    /// A live health snapshot for the Driver pane: rates are read
    /// now, not remembered from configure time — a device whose
    /// rate changes under a running chain is a health event.
    /// Transport and CPU are the pane's to fill (it owns the
    /// sampling clocks).
    func healthFacts() -> PipelineHealthFacts {
        func rate(of deviceID: AudioDeviceID?) -> Double? {
            guard let deviceID else { return nil }
            return sampleRateService.getActualSampleRate(deviceID: deviceID)
                ?? sampleRateService.getNominalSampleRate(deviceID: deviceID)
        }
        let pipeline = pipelineManager.renderPipeline
        return PipelineHealthFacts(
            activeMode: currentCaptureMode,
            pipelineRate: pipeline?.sampleRate,
            outputRate: rate(of: activeOutputDeviceID),
            inputRate: currentCaptureMode == .processTap ? nil : rate(of: activeInputDeviceID),
            inputFramesReceived: pipeline?.inputFramesReceived ?? 0,
            failedRouteCount: captureRetryState.failedCaptureModes.count
        )
    }

    // MARK: - Capture Liveness

    /// Starts the liveness watchdog for the just-started pipeline.
    /// The proof is a frame counter, not levels: frames advance even
    /// for digital silence on a live route. A quiet process-only tap
    /// may deliver no frames: keep re-arming until output starts. Startup
    /// proof samples across ~2.4 s; steady state re-proves every 5 s.
    /// TCC preflight for system audio capture (0 = granted). Private TCC call, as in Apple's
    /// own tap sample apps; nil symbol = unknown, which keeps the silence heuristic on.
    static var audioCaptureGranted: Bool {
        typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int32
        guard let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW),
              let symbol = dlsym(handle, "TCCAccessPreflight") else { return false }
        return unsafeBitCast(symbol, to: Preflight.self)("kTCCServiceAudioCapture" as CFString, nil) == 0
    }

    private func startLivenessMonitor() {
        livenessTask?.cancel()
        guard let pipeline = pipelineManager.renderPipeline else { return }
        let mode = currentCaptureMode
        let generation = routeGeneration
        livenessTask = Task { @MainActor [weak self] in
            var tapSamplesDB: [Float] = []
            // Hidden window = meters off = false "deaf"; measure anyway during the proof.
            pipeline.setMeterProbe(mode == .processTap)
            defer { pipeline.setMeterProbe(false) }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self, self.isMonitorCurrent(pipeline, generation: generation) else { return }
            if mode == .processTap {
                tapSamplesDB.append(pipeline.currentMeters().inputRmsDB.max() ?? -90)
            }
            var lastCount = pipeline.inputFramesReceived
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                switch self.verdict(for: pipeline, generation: generation, framesAdvanced: pipeline.inputFramesReceived > lastCount) {
                case .superseded:
                    return
                case .dead:
                    self.handleDeadCaptureRoute()
                    return
                case .idle:
                    lastCount = pipeline.inputFramesReceived
                    if mode == .processTap {
                        tapSamplesDB = [pipeline.currentMeters().inputRmsDB.max() ?? -90]
                    }
                    continue
                case .alive:
                    break
                }
                break
            }
            guard !Task.isCancelled else { return }
            if mode == .processTap {
                tapSamplesDB.append(pipeline.currentMeters().inputRmsDB.max() ?? -90)
            }
            // The tap's deafness check (B1), startup only: frames
            // advancing proves the tap is alive, not that it is
            // permitted to hear. Permission-deafness is present
            // from the first frame; mid-stream silence can be
            // honest content, so the steady-state guard below
            // stays frame-based.
            if TapDeafness.isDeaf(
                framesAdvanced: true,
                inputSamplesDB: tapSamplesDB,
                otherAppProducingOutput: !ChannelController.runningOutputBundleIDs().isEmpty,
                captureGranted: Self.audioCaptureGranted
            ) {
                self.logger.error("Capture liveness: Process Tap is delivering digital silence while other apps produce output")
                self.handleDeadCaptureRoute()
                return
            }
            pipeline.setMeterProbe(false)
            while !Task.isCancelled {
                lastCount = pipeline.inputFramesReceived
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                switch self.verdict(for: pipeline, generation: generation, framesAdvanced: pipeline.inputFramesReceived > lastCount) {
                case .superseded:
                    return
                case .dead:
                    self.handleDeadCaptureRoute()
                    return
                case .idle, .alive:
                    break
                }
            }
        }
    }

    /// The watchdog's verdict for one completed proof, scoped to the
    /// generation and pipeline it ran under (S1). Only `.dead` starts a
    /// retry: a stale generation or a superseded pipeline is discarded.
    private func verdict(for pipeline: RenderPipeline, generation: UInt64, framesAdvanced: Bool) -> RouteSeam.LivenessVerdict {
        seam.livenessVerdict(
            stamp: generation,
            pipelineStillCurrent: pipelineManager.renderPipeline === pipeline,
            statusActive: routingStatus.isActive,
            framesAdvanced: framesAdvanced,
            processProducingOutput: !framesAdvanced && processTapHardware.isAnyProcessRunningOutput(
                processObjectIDs: pipeline.activeCaptureMode == .processTap ? pipeline.tappedProcessObjectIDs : nil
            )
        )
    }


    private func isMonitorCurrent(_ pipeline: RenderPipeline, generation: UInt64) -> Bool {
        pipelineManager.renderPipeline === pipeline
            && routingStatus.isActive
            && seam.isCurrent(generation)
    }

    private func cancelLivenessMonitor() {
        livenessTask?.cancel()
        livenessTask = nil
    }

    /// Increments the route generation. Every event that changes what
    /// "the current route" means — output device change, nominal
    /// sample-rate change, capture-mode change, wake, or a
    /// watchdog-triggered retry — passes through here so stale async
    /// work (liveness proofs, restages) can be recognised and discarded.
    /// The generation is an internal consistency tool; it is never
    /// surfaced to the user.
    private func bumpRouteGeneration() {
        seam.advanceGeneration()
    }

    /// Records a device event and opens (or extends) the quiescence
    /// window. A storm of notifications becomes one restart against the
    /// settled state. Returns the scheduled commit interval; the caller
    /// should reschedule if a later event returns a shorter interval.
    /// The window lives here, not in `DeviceChangeCoordinator`, which
    /// stays a faithful event source.
    private func noteDeviceEvent(_ window: RouteSeam.Window) -> TimeInterval {
        seam.noteEvent(at: ProcessInfo.processInfo.systemUptime, window: window)
        return seam.deadline.map { max(0, $0 - ProcessInfo.processInfo.systemUptime) } ?? 0
    }

    /// The scheduled commit attempt: fires once the coalescing window
    /// has elapsed. Commits at most one route change per window,
    /// computed from the final device state, not the sequence. A
    /// commit is itself a route change — `closeWindow` advances the
    /// generation with it — so every proof and restage started inside
    /// the window is invalidated together.
    private func commitAfterQuiescence() {
        let now = ProcessInfo.processInfo.systemUptime
        guard seam.closeWindow(at: now) != nil else { return }

        // S3 at commit time: read back what the HAL would provide
        // against what is already committed. A storm that settled back
        // onto the running route needs no restart — and the window close
        // already bumped the generation, so the liveness monitor is
        // re‑started under it to keep the wake re‑proof alive.
        if !RouteSeam.commitNeedsRestart(
            settled: settledRouteTuple(),
            running: committedTuple,
            statusActive: routingStatus.isActive
        ) {
            logger.debug("Quiescent commit: settled route already committed — no restart")
            startLivenessMonitor()
            return
        }

        isQuiescentCommitReconfigure = true
        reconfigureRouting()
    }

    /// The route the settled device state resolves to right now: the
    /// selected output, its live nominal rate, and the capture mode in
    /// force. `nil` when there is no selected output or its rate cannot
    /// be read — an unreadable tuple is a restart, because the
    /// reconfigure produces an honest status rather than a guess.
    private func settledRouteTuple() -> RouteSeam.RouteTuple? {
        guard let outputUID = selectedOutputDeviceID,
              let deviceID = deviceProvider.deviceID(forUID: outputUID),
              let rate = sampleRateService.getActualSampleRate(deviceID: deviceID)
                ?? sampleRateService.getNominalSampleRate(deviceID: deviceID)
        else { return nil }
        return RouteSeam.RouteTuple(
            outputUID: outputUID,
            sampleRate: rate,
            captureMode: currentCaptureMode ?? effectiveCaptureMode
        )
    }

    /// Reads the committed tuple back from the HAL: the output device's
    /// live sample rate and the capture mode the pipeline actually
    /// runs. A tuple with no readable rate is `nil` — absence of a
    /// reading is not evidence of a wrong route, and failing on it would
    /// change the happy path on machines where the API returns nil
    /// (see `RouteSeam.matches`).
    private func readBackTuple(outputUID: String) -> RouteSeam.RouteTuple? {
        guard let deviceID = deviceProvider.deviceID(forUID: outputUID),
              let rate = sampleRateService.getActualSampleRate(deviceID: deviceID)
                ?? sampleRateService.getNominalSampleRate(deviceID: deviceID)
        else { return nil }
        return RouteSeam.RouteTuple(
            outputUID: outputUID,
            sampleRate: rate,
            captureMode: pipelineManager.renderPipeline?.activeCaptureMode ?? effectiveCaptureMode
        )
    }

    /// Schedules the quiescent commit attempt for a window type. Reschedules on every
    /// subsequent device event so a storm of notifications produces one
    /// restart against the settled state. The window lives here, not in
    /// `DeviceChangeCoordinator`, which stays a faithful event source.
    private func scheduleQuiescentCommit(window: RouteSeam.Window = .normal) {
        let interval = noteDeviceEvent(window)
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.commitAfterQuiescence()
        }
    }

    /// A wake event: increment the generation, open the 250 ms wake
    /// coalescing window, and re-prove liveness immediately rather than
    /// waiting for the steady-state 5 s tick. Nothing else about wake is
    /// special-cased — it flows through the same commit path as any
    /// device event. A stable route settles without a restart.
    public func handleWake() {
        guard routingStatus.isActive else { return }
        bumpRouteGeneration()
        // A wake is a route event: it may have killed the pipeline.
        // Re-prove liveness immediately rather than waiting for the
        // steady-state tick, and coalesce any device churn that follows.
        startLivenessMonitor()
        scheduleQuiescentCommit(window: .wake)
    }

    /// A capture route started but produced no audio. Rebuilds Process Tap
    /// once, then marks failed routes and tries the planner's next candidate,
    /// or stops routing honestly when no candidate remains.
    private func handleDeadCaptureRoute() {
        guard let failedMode = currentCaptureMode else { return }
        let next = captureRetryState.handleDeadRoute(
            failedMode,
            preference: captureMode,
            isManualMode: routingMode.isManual,
            supportsSharedMemory: driverAccess.hasSharedMemoryCapability()
        )
        if failedMode == .processTap && !processTapFailed {
            logger.info("Capture liveness: Process Tap silent, retrying once")
        } else {
            logger.error("Capture liveness: \(failedMode.displayName) produced no audio")
        }
        captureFallbackNotice = captureRetryState.notice
        if let next {
            captureModeOverride = next
            isCaptureFallbackRetry = true
            // Watchdog-triggered retry: new route generation.
            bumpRouteGeneration()
            reconfigureRouting()
            isCaptureFallbackRetry = false
        } else {
            stopRouting()
        }
    }
    
    // MARK: - Private Methods

    /// Ensures the driver is visible in CoreAudio, retrying if necessary.
    /// Calls `onVisible` if the driver is found, or sets an error state if not.
    private func ensureDriverVisible(onVisible: @escaping @MainActor () -> Void) {
        guard !driverAccess.isDriverVisible() else {
            onVisible()
            return
        }

        logger.warning("Driver not immediately visible, waiting for reconnection...")

        Task { @MainActor in
            if await driverAccess.findDriverDeviceWithRetry(initialDelayMs: 100, maxAttempts: 6) != nil {
                logger.info("Driver became visible, retrying routing configuration")
                onVisible()
            } else {
                logger.error("Driver did not become visible within timeout")
                routingStatus = .driverNotInstalled
                showDriverPrompt = true
            }
        }
    }

    private func stopPipeline() {
        pipelineManager.stopPipeline()

        // Stop device alive monitors
        stopDeviceAliveMonitors()

        // Clean up jack connection listener (Intel Macs)
        deviceChangeCoordinator.cleanupJackConnectionListener()
    }

    // MARK: - Device Alive Monitors

    /// Starts monitoring both input and output devices for removal.
    /// Uses `kAudioDevicePropertyDeviceIsAlive` for immediate, direct notification
    /// rather than waiting for the full device list to refresh.
    private func startDeviceAliveMonitors(inputDeviceID: AudioDeviceID, outputDeviceID: AudioDeviceID) {
        // Monitor input device
        let inputMonitor = DeviceAliveMonitor()
        inputMonitor.startMonitoring(deviceID: inputDeviceID) { [weak self] in
            guard let self = self else { return }
            self.logger.warning("Input device removed during active routing")
            self.routingStatus = .error("Input device removed")
            self.stopRouting()
        }
        inputDeviceAliveMonitor = inputMonitor

        // Monitor output device
        let outputMonitor = DeviceAliveMonitor()
        outputMonitor.startMonitoring(deviceID: outputDeviceID) { [weak self] in
            guard let self = self else { return }
            self.logger.warning("Output device removed during active routing")
            self.routingStatus = .error("Output device removed")
            self.stopRouting()
        }
        outputDeviceAliveMonitor = outputMonitor

        logger.debug("Device alive monitors started")
    }

    /// Stops monitoring devices for removal.
    private func stopDeviceAliveMonitors() {
        inputDeviceAliveMonitor?.stopMonitoring()
        inputDeviceAliveMonitor = nil
        outputDeviceAliveMonitor?.stopMonitoring()
        outputDeviceAliveMonitor = nil
    }

    private func syncDriverSampleRate(to outputDeviceID: AudioDeviceID) {
        // Get output device's sample rate (prefer actual over nominal)
        let outputRate = sampleRateService.getActualSampleRate(deviceID: outputDeviceID)
            ?? sampleRateService.getNominalSampleRate(deviceID: outputDeviceID)

        guard let targetRate = outputRate else {
            logger.warning("Could not determine output device sample rate")
            return
        }

        // Validate target rate is supported by the output device
        let syncRate: Float64
        if let availableRates = sampleRateService.getAvailableSampleRates(deviceID: outputDeviceID) {
            if rateIsSupported(targetRate, in: availableRates) {
                syncRate = targetRate
            } else {
                // Find closest supported rate
                let adjusted = closestRate(to: targetRate, in: availableRates)
                logger.warning("Output device doesn't support \(targetRate) Hz, using \(adjusted) Hz")
                syncRate = adjusted
            }
        } else {
            // Can't query available rates — proceed with target rate
            syncRate = targetRate
        }

        // Set driver to closest supported rate
        guard let setRate = driverAccess.setDriverSampleRate(matching: syncRate) else {
            logger.error("Failed to sync driver sample rate")
            return
        }

        logger.info("Driver sample rate synced: \(setRate) Hz (output: \(syncRate) Hz)")
    }

    /// Checks if a sample rate falls within any of the available rate ranges.
    private func rateIsSupported(_ rate: Float64, in ranges: [AudioValueRange]) -> Bool {
        ranges.contains { rate >= $0.mMinimum && rate <= $0.mMaximum }
    }

    /// Finds the closest available sample rate to the target.
    /// Extracts discrete rates (where mMinimum == mMaximum) and boundary rates from ranges.
    /// In practice, macOS audio devices always report discrete rates, so the range
    /// branch is rarely exercised. If a device did report a continuous range,
    /// only the range boundaries would be considered — not interior values.
    private func closestRate(to target: Float64, in ranges: [AudioValueRange]) -> Float64 {
        let discreteRates = ranges.flatMap { range -> [Float64] in
            // Discrete rates have mMinimum == mMaximum
            if range.mMinimum == range.mMaximum {
                return [range.mMinimum]
            }
            // For ranges, use the boundaries
            return [range.mMinimum, range.mMaximum]
        }

        let sorted = discreteRates.sorted()
        let closest = sorted.min(by: { abs($0 - target) < abs($1 - target) }) ?? target
        return closest
    }
    
    private func setupSampleRateListener(for outputDeviceID: AudioDeviceID) {
        // Clean up previous listener if any
        if let previousDeviceID = observedOutputDeviceID {
            sampleRateService.stopObservingSampleRateChanges(on: previousDeviceID)
        }
        
        observedOutputDeviceID = outputDeviceID
        
        // Start observing rate changes
        sampleRateService.observeSampleRateChanges(on: outputDeviceID) { [weak self] newRate in
            guard let self = self else { return }
            
            // Only sync if routing is active and in automatic mode
            guard case .active = self.routingStatus, !self.manualModeEnabled else { return }
            
            self.logger.info("Output device sample rate changed to \(newRate) Hz, re-syncing driver")

            // Validate rate against device's supported rates
            let syncRate: Float64
            if let availableRates = self.sampleRateService.getAvailableSampleRates(deviceID: outputDeviceID) {
                if self.rateIsSupported(newRate, in: availableRates) {
                    syncRate = newRate
                } else {
                    let adjusted = self.closestRate(to: newRate, in: availableRates)
                    self.logger.warning("Output device doesn't support \(newRate) Hz after change, using \(adjusted) Hz")
                    syncRate = adjusted
                }
            } else {
                syncRate = newRate
            }

            // Sync driver to new rate
            if let setRate = driverAccess.setDriverSampleRate(matching: syncRate) {
                // S2: read-back verification — confirm the HAL actually
                // applied the rate before committing a route change. A
                // mismatch is not an error; it is a new event (bump and
                // recoalesce against the settled state).
                guard abs(setRate - syncRate) < 1 else {
                    self.bumpRouteGeneration()
                    return
                }
                self.logger.info("Driver re-synced to \(setRate) Hz")
                
                // This is a route change: invalidate in-flight async work.
                self.bumpRouteGeneration()
                
                // Reconfigure pipeline after rate change settles
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.reconfigureRouting()
                }
            }
        }
    }
    
    private func handleSystemDefaultChanged(_ device: AudioDevice) {
        // In manual mode, ignore macOS changes
        guard routingMode.handlesSystemDefaultChanges else {
            logger.debug("handleSystemDefaultChanged: Manual mode - ignoring")
            return
        }

        logger.info("handleSystemDefaultChanged: macOS default output changed to '\(device.name)' (uid=\(device.uid))")
        logger.debug("handleSystemDefaultChanged: Current selected output: \(self.selectedOutputDeviceID ?? "nil")")

        // IMMEDIATE check for same device - no debounce delay
        // When user clicks the same device in System Settings, just restore the driver as default
        if device.uid == selectedOutputDeviceID {
            if routingStatus.isActive {
                logger.info("handleSystemDefaultChanged: Same device already selected - restoring driver as default")
                systemDefaultObserver.setDriverAsDefault(shortTimeout: true)
            } else {
                logger.info("handleSystemDefaultChanged: Same device selected but routing inactive - reconfiguring")
                reconfigureRouting()
            }
            return
        }

        // Different device - reconfigure immediately (no debounce)
        // Save current output to history before switching
        if let current = selectedOutputDeviceID,
           current != DRIVER_DEVICE_UID,
           current != device.uid {
            deviceChangeCoordinator.addToHistory(current)
            logger.debug("handleSystemDefaultChanged: Saved previous output to history")
        }

        // Update output device
        selectedOutputDeviceID = device.uid
        logger.info("handleSystemDefaultChanged: Switching to '\(device.name)'")

        // This is a route change: invalidate any in-flight async work
        // (liveness proofs, restages) from the previous generation.
        bumpRouteGeneration()

        // Reconfigure routing immediately
        reconfigureRouting()
    }

    // MARK: - Device Change Handlers
    
    /// Called when the selected output device is missing from available devices.
    private func handleSelectedOutputMissing(_ uid: String) {
        // Only handle in automatic mode (driver is used)
        guard routingMode.handlesBuiltInDeviceChanges else {
            logger.debug("Manual mode: ignoring missing device")
            return
        }
        
        logger.info("Selected output device missing: \(uid)")
        // A device event: coalesce rather than restart immediately.
        // (scheduleQuiescentCommit notes the event itself.)
        scheduleQuiescentCommit()
        
        // Find replacement device
        if let replacement = deviceChangeCoordinator.findReplacementDevice(for: selectedOutputDeviceID) {
            selectedOutputDeviceID = replacement.uid
            logger.info("Using replacement device: \(replacement.name)")
            // Route changed: invalidate in-flight async work.
            bumpRouteGeneration()
            reconfigureRouting()
        } else {
            // No output device available
            logger.error("No output device available after disconnect")
            routingStatus = .error("No output device available")
        }
    }
    
    /// Called when a previously missing selected output device
    /// is available again — the recovery half of
    /// handleSelectedOutputMissing. A transient absence (the
    /// coreaudiod restart inside a driver install) parked the
    /// coordinator in its no-device error with no way back;
    /// the restored signal is what retries. The enumeration
    /// service only emits it after reporting the same device
    /// missing, so this cannot fire on ordinary device churn.
    private func handleSelectedOutputRestored(_ uid: String) {
        guard routingMode.handlesBuiltInDeviceChanges else {
            logger.debug("Manual mode: ignoring restored device")
            return
        }
        guard !isReconfiguring else {
            logger.debug("Already reconfiguring - ignoring restored device")
            return
        }
        guard !routingStatus.isActive else {
            logger.debug("Routing already active - ignoring restored device")
            return
        }
        logger.info("Selected output device restored: \(uid) - reconfiguring")
        // Route restored: invalidate in-flight async work.
        bumpRouteGeneration()
        reconfigureRouting()
    }

    /// Called when built-in devices are removed (Apple Silicon: headphones unplugged).
    private func handleBuiltInDevicesRemoved() {
        guard routingMode.handlesBuiltInDeviceChanges else { return }
        
        // Clear missing tracking so we can detect if current device is missing
        deviceChangeCoordinator.clearMissingTracking()
    }
    
    /// Called when a single built-in device is added (Apple Silicon: headphones plugged in).
    private func handleBuiltInDeviceAdded(_ device: AudioDevice) {
        guard routingMode.handlesBuiltInDeviceChanges else {
            logger.debug("handleBuiltInDeviceAdded: Manual mode - ignoring")
            return
        }
        
        // Don't reconfigure during reconfiguration
        guard !isReconfiguring else {
            logger.debug("handleBuiltInDeviceAdded: Already reconfiguring - ignoring")
            return
        }
        
        // Only switch if currently routing to a built-in device
        // (Never switch away from USB/Bluetooth/HDMI - matches macOS behaviour)
        guard let currentUID = selectedOutputDeviceID,
              let currentDevice = deviceProvider.device(forUID: currentUID),
              currentDevice.transportType == kAudioDeviceTransportTypeBuiltIn else {
            logger.debug("handleBuiltInDeviceAdded: Current output is not built-in, not switching")
            return
        }
        
        logger.info("Headphones detected: '\(device.name)', switching output")
        
        // Save current device to history for restoration when headphones unplugged
        if currentUID != DRIVER_DEVICE_UID,
           currentUID != device.uid {
            deviceChangeCoordinator.addToHistory(currentUID)
        }
        
        // Switch to the new built-in device (headphones)
        selectedOutputDeviceID = device.uid
        reconfigureRouting()
    }
    
    private func findFallbackOutputDevice() -> AudioDevice? {
        deviceProvider.selectFallbackOutputDevice()
    }
    
    // MARK: - Init-time Configuration

    // MARK: - Driver Name Management

    /// Updates the driver name based on current routing state.
    /// Delegates to DriverNameManager for the CoreAudio refresh workaround.
    /// This method is synchronous and returns immediately.
    /// The caller is responsible for calling setDriverAsDefault() before starting the pipeline.
    /// - Returns: `true` if name was set successfully, `false` otherwise.
    @discardableResult
    private func updateDriverName() -> Bool {
        let outputDevice = selectedOutputDeviceID.flatMap { deviceProvider.device(forUID: $0) }

        return driverNameManager.updateDriverName(
            manualMode: manualModeEnabled,
            selectedOutputUID: selectedOutputDeviceID,
            selectedOutputDevice: outputDevice
        )
    }
}
