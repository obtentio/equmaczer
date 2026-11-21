// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
/// Constants for the EQ layer system.
enum EQLayerConstants {
    /// Maximum number of EQ layers per channel.
    /// Pre-allocated at pipeline init. Unused layers are passthrough (zero CPU cost).
    static let maxLayerCount = 4

    /// Well-known layer indices.
    /// Layer 0 is always the user EQ.
    static let userEQLayerIndex = 0

    /// Layer 1 carries the composed correction: the output device's
    /// correction profile, preference trims, and loudness shelves.
    /// Owned by `CorrectionController`; never edited as user EQ.
    static let correctionLayerIndex = 1

    /// Layer 2 carries the active channel's treatment (A3): a
    /// factory preset chosen for the channel (Music / Calls / Film /
    /// Games) whose apps are currently producing sound. Owned by
    /// `ChannelController`; never edited as user EQ.
    static let channelLayerIndex = 2

    /// Layer 3 carries the hearing layer (A5): the listener's
    /// relative per-ear Low/High shelves, staged per channel (left
    /// shelves to the left chain, right to the right). Owned by
    /// `HearingController`; never edited as user EQ.
    static let hearingLayerIndex = 3
}