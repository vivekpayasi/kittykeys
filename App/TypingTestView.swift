import KeyboardCore
import SwiftUI

/// The keyboard a run used, as the user picks it. The raw value is saved as `TypingRun.keyboard`.
enum TestKeyboard: String, CaseIterable, Identifiable {
    case catkeys = "catkeys"
    case apple = "Apple"
    case other = "Other"

    var id: Self { self }
}

/// A run in progress: its sentences, which one shows, and the numbers so far. The typed text isn't here; it lives
/// in the view only while its sentence shows.
struct RunProgress {
    static let sentenceCount = 5

    var sentences: [TypingSentence]
    var index = 0
    /// When the current sentence's first edit came, in `ProcessInfo.systemUptime` seconds, which only go forward.
    var startedAt: TimeInterval?
    var seconds = 0.0
    var targetCharacters = 0
    var errorsLeft = 0
    var corrections = 0

    var sentence: TypingSentence { sentences[index] }
}

/// A typing test: 5 sentences, then errors left, corrections and speed, with past runs below. It measures how
/// accurately taps land, to compare catkeys builds with each other and with Apple's keyboard.
/// Only the numbers are saved, in the app's own defaults; the typed text never is. Nothing leaves the phone.
struct TypingTestView: View {
    /// The keyboard's heartbeat, which suggests the keyboard in use. nil when this install has no App Group.
    let heartbeat: SettingsStore?
    private let runStore: TypingRunStore

    @Environment(\.scenePhase) private var scenePhase
    @State private var keyboard = TestKeyboard.apple
    /// Set once the user picks a keyboard, so the heartbeat's suggestion no longer replaces their choice.
    @State private var keyboardPicked = false
    @State private var history: [TypingRun] = []
    @State private var progress: RunProgress?
    @State private var typed = ""
    @State private var lastRun: TypingRun?
    @State private var sentencesMissing = false
    @FocusState private var fieldFocused: Bool

    #if DEBUG
    /// Built once per launch, as SwiftUI may build this view many times.
    private static let screenshotScene = ScreenshotScene(UserDefaults.standard.string(forKey: "catkeysTypingTestScene"))
    #endif

    init(heartbeat: SettingsStore?) {
        self.heartbeat = heartbeat
        #if DEBUG
        if let scene = Self.screenshotScene {
            runStore = scene.runStore
            _progress = State(initialValue: scene.progress)
            _typed = State(initialValue: scene.typed)
            _lastRun = State(initialValue: scene.lastRun)
            return
        }
        #endif
        runStore = TypingRunStore(defaults: .standard)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let progress {
                    runForm(progress)
                } else if let lastRun {
                    summaryForm(lastRun)
                } else {
                    readyForm
                }
            }
            .navigationTitle("Typing test")
        }
        .onAppear {
            history = runStore.load()
            suggestKeyboard()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { suggestKeyboard() }
        }
    }

    // MARK: - Screens

    private var readyForm: some View {
        Form {
            Section {
                Picker("Keyboard", selection: pickedKeyboard) {
                    ForEach(TestKeyboard.allCases) { keyboard in
                        Text(keyboard.rawValue).tag(keyboard)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Keyboard")
            } footer: {
                Text("The keyboard you'll type with. Switch with 🌐.")
            }
            Section {
                Button("Start", action: start)
            } footer: {
                if sentencesMissing {
                    Text("Couldn't load the sentences.")
                } else {
                    Text("Type 5 short sentences, tapping Done after each. Only the numbers are saved, never what you type.")
                }
            }
            historySection
        }
    }

    private func runForm(_ progress: RunProgress) -> some View {
        Form {
            Section("Sentence \(progress.index + 1) of \(progress.sentences.count)") {
                Text(progress.sentence.text)
                    .font(.title3)
            }
            Section {
                TextField("Type the sentence", text: typedText, axis: .vertical)
                    // Without autocorrect, Apple's keyboard is measured on taps alone, like catkeys.
                    .autocorrectionDisabled(true)
                    .focused($fieldFocused)
                // An explicit button, not Return: keyboards treat Return differently.
                Button("Done", action: submit)
                    .disabled(TypingMetrics.normalized(typed).isEmpty)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Stop", action: stop)
            }
        }
        .onAppear { fieldFocused = true }
    }

    private func summaryForm(_ run: TypingRun) -> some View {
        Form {
            Section {
                LabeledContent("Errors left", value: run.errorsLeftText)
                LabeledContent("Corrections", value: "\(run.corrections)")
                LabeledContent("Speed", value: "\(run.wordsPerMinuteText) WPM")
            } header: {
                Text("This run: \(run.keyboard)")
            } footer: {
                Text("""
                    Errors left: characters still wrong or missing when you tapped Done.
                    Corrections: characters you deleted while typing.
                    Speed: words per minute, counting 5 characters as a word.
                    """)
            }
            Section {
                Button("New run") { lastRun = nil }
            }
            historySection
        }
    }

    @ViewBuilder private var historySection: some View {
        if !history.isEmpty {
            Section("History") {
                ForEach(history.indices, id: \.self) { index in
                    HistoryRow(run: history[index])
                }
            }
        }
    }

    // MARK: - Actions

    /// The picker's binding: a pick by the user sticks.
    private var pickedKeyboard: Binding<TestKeyboard> {
        Binding(
            get: { keyboard },
            set: { newValue in
                keyboard = newValue
                keyboardPicked = true
            })
    }

    /// The field's binding. The first edit starts the sentence's timer, and each edit that shortens the text adds
    /// the characters it removed to the corrections. Clearing the field between sentences doesn't come through here.
    private var typedText: Binding<String> {
        Binding(
            get: { typed },
            set: { newValue in
                guard newValue != typed, var run = progress else { return }
                if run.startedAt == nil { run.startedAt = ProcessInfo.processInfo.systemUptime }
                run.corrections += max(0, typed.count - newValue.count)
                progress = run
                typed = newValue
            })
    }

    /// catkeys if the keyboard opened in the last minute, else Apple's, until the user picks.
    private func suggestKeyboard() {
        guard progress == nil, !keyboardPicked else { return }
        let opened = heartbeat?.lastKeyboardOpen
        keyboard = opened.map { Date.now.timeIntervalSince($0) < 60 } == true ? .catkeys : .apple
    }

    private func start() {
        guard let sentences = try? TypingSentences.bundled(), sentences.count >= RunProgress.sentenceCount else {
            sentencesMissing = true
            return
        }
        sentencesMissing = false
        typed = ""
        lastRun = nil
        progress = RunProgress(sentences: Array(sentences.shuffled().prefix(RunProgress.sentenceCount)))
    }

    private func submit() {
        guard var run = progress else { return }
        let target = run.sentence.text
        run.errorsLeft += TypingMetrics.editDistance(target, TypingMetrics.normalized(typed))
        run.targetCharacters += target.count
        if let startedAt = run.startedAt {
            run.seconds += ProcessInfo.processInfo.systemUptime - startedAt
        }
        run.startedAt = nil
        run.index += 1
        typed = ""
        guard run.index == run.sentences.count else {
            progress = run
            return
        }
        let finished = TypingRun(
            date: .now, keyboard: keyboard.rawValue, targetCharacters: run.targetCharacters,
            errorsLeft: run.errorsLeft, corrections: run.corrections, seconds: run.seconds)
        runStore.append(finished)
        history = runStore.load()
        fieldFocused = false
        progress = nil
        lastRun = finished
    }

    /// Ends the run without saving it.
    private func stop() {
        fieldFocused = false
        progress = nil
        typed = ""
    }
}

/// One past run: the keyboard and date, then its three numbers in columns that line up from row to row.
private struct HistoryRow: View {
    let run: TypingRun

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(run.keyboard)
                    .font(.headline)
                Spacer()
                Text(run.date, format: .dateTime.day().month().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline) {
                HistoryNumber(value: run.errorsLeftText, label: "errors left")
                HistoryNumber(value: "\(run.corrections)", label: "corrections")
                HistoryNumber(value: run.wordsPerMinuteText, label: "WPM")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HistoryNumber: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension TypingRun {
    /// Such as "3 (1.4%)".
    var errorsLeftText: String {
        "\(errorsLeft) (\(errorRate.formatted(.percent.precision(.fractionLength(1)))))"
    }

    /// Such as "48".
    var wordsPerMinuteText: String {
        wordsPerMinute.formatted(.number.precision(.fractionLength(0)))
    }
}

#if DEBUG
// MARK: - Simulator screenshots (debug builds only)

/// `scripts/sim-screenshots.sh` opens the tab in a set state with `-catkeysTypingTestScene <scene>`:
/// - `run`: a run at sentence 2 of 5, partly typed.
/// - `summary`: a finished run, with invented sample runs as history.
/// The sample runs live in their own defaults suite, emptied at each launch, so they never mix with real history.
private struct ScreenshotScene {
    private static let suite = "catkeys.screenshots.typingTest"

    let runStore: TypingRunStore
    var progress: RunProgress?
    var typed = ""
    var lastRun: TypingRun?

    init?(_ name: String?) {
        guard let name else { return nil }
        UserDefaults.standard.removePersistentDomain(forName: Self.suite)
        guard let defaults = UserDefaults(suiteName: Self.suite) else { return nil }
        runStore = TypingRunStore(defaults: defaults)
        switch name {
        case "run":
            guard let sentences = try? TypingSentences.bundled(), sentences.count >= RunProgress.sentenceCount else {
                return nil
            }
            let picked = Array(sentences.suffix(RunProgress.sentenceCount))
            progress = RunProgress(
                sentences: picked, index: 1, startedAt: ProcessInfo.processInfo.systemUptime - 4,
                seconds: 9.5, targetCharacters: picked[0].text.count, errorsLeft: 1, corrections: 2)
            typed = String(picked[1].text.prefix(22))
        case "summary":
            // Invented numbers, oldest first so the newest ends up on top.
            let now = Date.now
            let samples = [
                TypingRun(date: now.addingTimeInterval(-86_400 - 600), keyboard: "Apple",
                          targetCharacters: 188, errorsLeft: 2, corrections: 6, seconds: 43.1),
                TypingRun(date: now.addingTimeInterval(-86_400), keyboard: "catkeys",
                          targetCharacters: 192, errorsLeft: 7, corrections: 15, seconds: 58.2),
                TypingRun(date: now.addingTimeInterval(-1_500), keyboard: "Apple",
                          targetCharacters: 204, errorsLeft: 1, corrections: 5, seconds: 44.0),
                TypingRun(date: now.addingTimeInterval(-90), keyboard: "catkeys",
                          targetCharacters: 199, errorsLeft: 2, corrections: 8, seconds: 49.6),
            ]
            samples.forEach(runStore.append)
            lastRun = samples.last
        default:
            return nil
        }
    }
}
#endif
