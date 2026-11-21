// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

/// C2: the blind A/B sheet. Labels hidden, levels matched, one
/// pick, winner revealed after — and nothing kept: no scores, no
/// history, the test exists only while the sheet is open.
struct BlindABView: View {
    enum Mode {
        case preset
        case correction
    }

    let store: EqumaczerStore
    let correctionController: CorrectionController
    let mode: Mode

    @State private var controller: BlindABController?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let controller {
                BlindABContent(controller: controller, store: store, mode: mode) {
                    dismiss()
                }
            } else {
                Text("Preparing…")
                    .font(.eqT1)
                    .foregroundStyle(Color.eqG60)
            }
        }
        .padding(16)
        .frame(width: 400)
        .onAppear {
            guard controller == nil else { return }
            let created = BlindABController(store: store, correctionController: correctionController)
            if mode == .correction {
                created.startCorrectionTest()
            }
            controller = created
        }
        .onDisappear {
            controller?.end()
        }
    }
}

private struct BlindABContent: View {
    @ObservedObject var controller: BlindABController
    let store: EqumaczerStore
    let mode: BlindABView.Mode
    let onDone: () -> Void

    var body: some View {
        if let session = controller.session {
            sessionBody(session)
        } else if mode == .preset {
            chooser
        } else {
            Text("No correction is staged for a test.")
                .font(.eqT1)
                .foregroundStyle(Color.eqG60)
        }
    }

    // MARK: - Chooser (preset mode)

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Blind test")
                .font(.eqT1)
                .foregroundStyle(Color.eqG60)
            Text("Pick a preset. You will hear it and your current sound as A and B — labels hidden, levels matched — and choose before you know which was which.")
                .font(.eqT1)
                .foregroundStyle(Color.eqG80)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(store.presetManager.builtInPresets + store.presetManager.userPresets) { preset in
                Button {
                    controller.startPresetTest(preset)
                } label: {
                    Text(preset.metadata.name)
                        .font(.eqT1)
                        .foregroundStyle(Color.eqG95)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Session

    @ViewBuilder
    private func sessionBody(_ session: BlindABSession.State) -> some View {
        switch session.phase {
        case .listening:
            VStack(alignment: .leading, spacing: 12) {
                Text("Which sounds better?")
                    .font(.eqT2)
                    .foregroundStyle(Color.eqG95)
                HStack(spacing: 10) {
                    sideButton(.a, session: session)
                    sideButton(.b, session: session)
                }
                Text(matchLine)
                    .font(.eqT0)
                    .foregroundStyle(Color.eqG60)
                HStack(spacing: 10) {
                    preferButton(.a, session: session)
                    preferButton(.b, session: session)
                }
                if !session.canPick {
                    Text("Hear both sides first.")
                        .font(.eqT0)
                        .foregroundStyle(Color.eqG60)
                }
                Button {
                    controller.cancel()
                    onDone()
                } label: {
                    Text("End test").font(.eqT1).foregroundStyle(Color.eqG60)
                }
                .buttonStyle(.plain)
            }
        case .revealed(let winnerIsCandidate):
            let winnerLetter: BlindABSession.Letter = winnerIsCandidate
                ? (session.candidateIsA ? .a : .b)
                : (session.candidateIsA ? .b : .a)
            VStack(alignment: .leading, spacing: 12) {
                Text("\(winnerLetter == .a ? "A" : "B") was \(winnerIsCandidate ? "‘\(controller.candidateName ?? "the candidate")’" : "your current sound").")
                    .font(.eqT2)
                    .foregroundStyle(Color.eqG95)
                    .fixedSize(horizontal: false, vertical: true)
                Text("It is playing now.")
                    .font(.eqT1)
                    .foregroundStyle(Color.eqG60)
                HStack(spacing: 10) {
                    Button {
                        onDone()
                    } label: {
                        Text("Done").font(.eqT1).foregroundStyle(Color.eqG95)
                    }
                    .buttonStyle(.plain)
                    Button {
                        controller.useOtherSide()
                        onDone()
                    } label: {
                        Text("Use the other one").font(.eqT1).foregroundStyle(Color.eqG60)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var matchLine: String {
        switch mode {
        case .correction:
            return "Levels matched by the preview."
        case .preset:
            return controller.levelsMatched
                ? "Levels matched."
                : "Level matching settles as you listen to both sides."
        }
    }

    private func sideButton(_ letter: BlindABSession.Letter, session: BlindABSession.State) -> some View {
        let isCurrent = session.current == letter
        let heard = letter == .a ? session.heardA : session.heardB
        return Button {
            controller.showSide(letter)
        } label: {
            VStack(spacing: 2) {
                Text(letter == .a ? "A" : "B")
                    .font(.eqT3)
                    .foregroundStyle(Color.eqG95)
                Text(isCurrent ? "playing" : (heard ? "heard" : "not heard"))
                    .font(.eqT0)
                    .foregroundStyle(Color.eqG60)
            }
            .frame(width: 90, height: 56)
            .background(isCurrent ? Color.eqG20 : Color.eqG10)
        }
        .buttonStyle(.plain)
    }

    private func preferButton(_ letter: BlindABSession.Letter, session: BlindABSession.State) -> some View {
        Button {
            controller.pick(letter)
        } label: {
            Text("I prefer \(letter == .a ? "A" : "B")")
                .font(.eqT1)
                .foregroundStyle(session.canPick ? Color.eqG95 : Color.eqG60)
        }
        .buttonStyle(.plain)
        .disabled(!session.canPick)
    }
}
