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
    /// When Start was tapped, to tell whether the catkeys keyboard opened during the run.
    var startedAt = Date.now
    /// Times each sentence from its first edit to Done, stopped while the app isn't active.
    var stopwatch = TypingStopwatch()
    var targetCharacters = 0
    var typedCharacters = 0
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
    /// Set once the user picks a keyboard on the ready screen, so the heartbeat's suggestion no longer replaces
    /// their choice there. Cleared each time the ready screen appears.
    @State private var keyboardPicked = false
    @State private var history: [TypingRun] = []
    @State private var progress: RunProgress?
    @State private var typed = ""
    @State private var lastRun: TypingRun?
    /// Whether the catkeys keyboard opened after the last run's Start, which offers to relabel it as catkeys.
    @State private var catkeysOpenedDuringLastRun = false
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
            _catkeysOpenedDuringLastRun = State(initialValue: scene.catkeysOpenedDuringLastRun)
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
        .onAppear { history = runStore.load() }
        .onChange(of: scenePhase) { _, phase in
            let now = ProcessInfo.processInfo.systemUptime
            if phase == .active {
                progress?.stopwatch.resume(at: now)
                suggestKeyboard()
            } else {
                progress?.stopwatch.pause(at: now)
            }
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
        // Each time: on first show, after New run and after Stop. A pick from before a run says nothing about the
        // keyboard in use now.
        .onAppear {
            keyboardPicked = false
            suggestKeyboard()
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
                    Speed: words per minute of what you typed, counting 5 characters as a word.
                    """)
            }
            if catkeysOpenedDuringLastRun && run.keyboard != TestKeyboard.catkeys.rawValue {
                Section {
                    Text("Looks like you used catkeys — relabel?")
                    Button("Relabel as catkeys", action: relabelLastRunAsCatkeys)
                }
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
                ForEach(history) { run in
                    HistoryRow(run: run)
                }
                .onDelete(perform: deleteRuns)
            }
        }
    }

    // MARK: - Actions

    /// The picker's binding: a pick by the user sticks while the ready screen shows.
    private var pickedKeyboard: Binding<TestKeyboard> {
        Binding(
            get: { keyboard },
            set: { newValue in
                keyboard = newValue
                keyboardPicked = true
            })
    }

    /// The field's binding. Each edit tells the stopwatch, which starts the sentence's clock on the first one, and
    /// each edit that shortens the text adds the characters it removed to the corrections. Clearing the field
    /// between sentences doesn't come through here.
    private var typedText: Binding<String> {
        Binding(
            get: { typed },
            set: { newValue in
                guard newValue != typed, var run = progress else { return }
                run.stopwatch.edit(at: ProcessInfo.processInfo.systemUptime)
                run.corrections += max(0, typed.count - newValue.count)
                progress = run
                typed = newValue
            })
    }

    /// catkeys if its keyboard opened in the last minute, else Apple's, unless the user has picked. Only on the
    /// ready screen: a run's label is settled when it starts.
    private func suggestKeyboard() {
        guard progress == nil, lastRun == nil, !keyboardPicked else { return }
        let opened = heartbeat?.lastKeyboardOpen
        keyboard = opened.map { Date.now.timeIntervalSince($0) < 60 } == true ? .catkeys : .apple
    }

    /// Draws 5 sentences, 3 in one language and 2 in the other, interleaved. The language with 3 takes turns from
    /// run to run.
    private func start() {
        guard let sentences = try? TypingSentences.bundled(), sentences.count >= RunProgress.sentenceCount,
              let majority = TypingSentences.nextMajority(after: runStore.lastMajorityLanguage, in: sentences)
        else {
            sentencesMissing = true
            return
        }
        runStore.lastMajorityLanguage = majority
        var generator = SystemRandomNumberGenerator()
        let drawn = TypingSentences.balancedDraw(
            sentences, count: RunProgress.sentenceCount, majority: majority, using: &generator)
        sentencesMissing = false
        typed = ""
        lastRun = nil
        catkeysOpenedDuringLastRun = false
        progress = RunProgress(sentences: drawn)
    }

    private func submit() {
        guard var run = progress else { return }
        let target = run.sentence.text
        let submitted = TypingMetrics.normalized(typed)
        run.errorsLeft += TypingMetrics.editDistance(target, submitted)
        run.targetCharacters += target.count
        run.typedCharacters += submitted.count
        run.stopwatch.finishSentence(at: ProcessInfo.processInfo.systemUptime)
        run.index += 1
        typed = ""
        guard run.index == run.sentences.count else {
            progress = run
            return
        }
        let finished = TypingRun(
            date: .now, keyboard: keyboard.rawValue, targetCharacters: run.targetCharacters,
            typedCharacters: run.typedCharacters, errorsLeft: run.errorsLeft, corrections: run.corrections,
            seconds: run.stopwatch.seconds)
        runStore.append(finished)
        history = runStore.load()
        // The keyboard writes its heartbeat each time it appears, which for a run is just after Start.
        catkeysOpenedDuringLastRun = heartbeat?.lastKeyboardOpen.map { $0 > run.startedAt } ?? false
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

    private func relabelLastRunAsCatkeys() {
        guard var run = lastRun else { return }
        run.keyboard = TestKeyboard.catkeys.rawValue
        runStore.replace(run)
        history = runStore.load()
        lastRun = run
    }

    private func deleteRuns(at offsets: IndexSet) {
        for id in offsets.map({ history[$0].id }) {
            runStore.remove(id: id)
        }
        history = runStore.load()
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
/// - `relabel`: the same, but the run is labelled Apple while the catkeys keyboard opened during it.
/// The sample runs live in their own defaults suite, emptied at each launch, so they never mix with real history.
private struct ScreenshotScene {
    private static let suite = "catkeys.screenshots.typingTest"

    let runStore: TypingRunStore
    var progress: RunProgress?
    var typed = ""
    var lastRun: TypingRun?
    var catkeysOpenedDuringLastRun = false

    init?(_ name: String?) {
        guard let name else { return nil }
        UserDefaults.standard.removePersistentDomain(forName: Self.suite)
        guard let defaults = UserDefaults(suiteName: Self.suite) else { return nil }
        runStore = TypingRunStore(defaults: defaults)
        switch name {
        case "run":
            guard let sentences = try? TypingSentences.bundled() else { return nil }
            let english = sentences.filter { $0.language == "en" }
            let hinglish = sentences.filter { $0.language == "hi-Latn" }
            guard english.count >= 3, hinglish.count >= 4 else { return nil }
            let picked = [english[0], hinglish[2], english[1], hinglish[3], english[2]]
            let now = ProcessInfo.processInfo.systemUptime
            var stopwatch = TypingStopwatch()
            stopwatch.edit(at: now - 14)
            stopwatch.finishSentence(at: now - 5)
            stopwatch.edit(at: now - 4)
            progress = RunProgress(
                sentences: picked, index: 1, startedAt: .now.addingTimeInterval(-16), stopwatch: stopwatch,
                targetCharacters: picked[0].text.count, typedCharacters: picked[0].text.count, errorsLeft: 1,
                corrections: 2)
            typed = String(picked[1].text.prefix(22))
        case "summary", "relabel":
            // Invented numbers, oldest first so the newest ends up on top.
            let now = Date.now
            var samples = [
                TypingRun(date: now.addingTimeInterval(-86_400 - 600), keyboard: "Apple", targetCharacters: 188,
                          typedCharacters: 187, errorsLeft: 2, corrections: 6, seconds: 43.1),
                TypingRun(date: now.addingTimeInterval(-86_400), keyboard: "catkeys", targetCharacters: 192,
                          typedCharacters: 194, errorsLeft: 7, corrections: 15, seconds: 58.2),
                TypingRun(date: now.addingTimeInterval(-1_500), keyboard: "Apple", targetCharacters: 204,
                          typedCharacters: 204, errorsLeft: 1, corrections: 5, seconds: 44.0),
                TypingRun(date: now.addingTimeInterval(-90), keyboard: "catkeys", targetCharacters: 199,
                          typedCharacters: 198, errorsLeft: 2, corrections: 8, seconds: 49.6),
            ]
            if name == "relabel" {
                samples[samples.count - 1].keyboard = "Apple"
                catkeysOpenedDuringLastRun = true
            }
            samples.forEach(runStore.append)
            lastRun = samples.last
        default:
            return nil
        }
    }
}
#endif
