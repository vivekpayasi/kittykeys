import Foundation
import Testing
import KeyboardCore

/// Each test gets its own defaults suite, named by an absolute path inside its own temporary folder, as in
/// `SettingsTests`. The suite and the folder are removed when the test ends.
final class CodeFieldHandOffTests {
    let suiteFolder: URL
    let suiteName: String
    let defaults: UserDefaults
    let handOff: CodeFieldHandOff

    static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    static let field = UUID()
    static let otherField = UUID()
    static let thirdField = UUID()
    static let fourthField = UUID()

    init() {
        suiteFolder = FileManager.default.temporaryDirectory.appendingPathComponent("kittykeys-tests-\(UUID())")
        suiteName = suiteFolder.appendingPathComponent("handoff").path
        defaults = UserDefaults(suiteName: suiteName)!
        handOff = CodeFieldHandOff(defaults: defaults)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: suiteFolder)
    }

    @Test func handsOffAFieldItHasNotSeen() {
        #expect(handOff.decide(document: Self.field, now: Self.start) == .handOff)
    }

    @Test func waitsForIOSToNameTheField() {
        #expect(handOff.decide(document: nil, now: Self.start) == .noDocument)
        // Nothing was remembered.
        #expect(handOff.decide(document: Self.field, now: Self.start) == .handOff)
    }

    /// The user pressed 🌐 to come back: kittykeys stays, however long they took.
    @Test func staysWhenBackInTheFieldItHandedOff() {
        #expect(handOff.decide(document: Self.field, now: Self.start) == .handOff)
        #expect(handOff.decide(document: Self.field, now: Self.start + 10) == .sameField)
        #expect(handOff.decide(document: Self.field, now: Self.start + 3600) == .sameField)
    }

    /// A code split over several boxes is several fields; once the user came back, kittykeys stays for the rest.
    @Test func staysForOtherFieldsSoonAfterAHandOff() {
        #expect(handOff.decide(document: Self.field, now: Self.start) == .handOff)
        #expect(handOff.decide(document: Self.otherField, now: Self.start + 59) == .quietPeriod)
        #expect(handOff.decide(document: Self.thirdField, now: Self.start + 59 + 60) == .handOff)
    }

    /// Coming back may take minutes, as when reading a code from an authenticator app; the next box still stays.
    @Test func aReturnRestartsTheQuietPeriod() {
        #expect(handOff.decide(document: Self.field, now: Self.start) == .handOff)
        #expect(handOff.decide(document: Self.field, now: Self.start + 300) == .sameField)
        #expect(handOff.decide(document: Self.otherField, now: Self.start + 330) == .quietPeriod)
        // Each box restarts it too.
        #expect(handOff.decide(document: Self.thirdField, now: Self.start + 380) == .quietPeriod)
        #expect(handOff.decide(document: Self.fourthField, now: Self.start + 440) == .handOff)
    }

    /// The field kittykeys stayed in is never handed off later, as when the user leaves for an authenticator app.
    @Test func neverHandsOffTheFieldItStayedIn() {
        #expect(handOff.decide(document: Self.field, now: Self.start) == .handOff)
        #expect(handOff.decide(document: Self.otherField, now: Self.start + 30) == .quietPeriod)
        #expect(handOff.decide(document: Self.otherField, now: Self.start + 600) == .sameField)
    }

    @Test func aClockSetBackDoesNotKeepKittykeys() {
        #expect(handOff.decide(document: Self.field, now: Self.start) == .handOff)
        #expect(handOff.decide(document: Self.otherField, now: Self.start - 3600) == .handOff)
    }

    @Test func remembersTheLatestHandOffOnly() {
        #expect(handOff.decide(document: Self.field, now: Self.start) == .handOff)
        #expect(handOff.decide(document: Self.otherField, now: Self.start + 120) == .handOff)
        #expect(handOff.decide(document: Self.field, now: Self.start + 240) == .handOff)
    }

    /// iOS makes a new keyboard process when it likes, so the memory lives in the defaults.
    @Test func memoryOutlivesTheInstance() {
        #expect(handOff.decide(document: Self.field, now: Self.start) == .handOff)
        let later = CodeFieldHandOff(defaults: UserDefaults(suiteName: suiteName)!)
        #expect(later.decide(document: Self.field, now: Self.start + 3600) == .sameField)
    }

    @Test func corruptDateForgetsTheHandOff() {
        defaults.set(Self.field.uuidString, forKey: "catkeys.codeHandOff.document")
        defaults.set("yesterday", forKey: "catkeys.codeHandOff.date")
        #expect(handOff.decide(document: Self.field, now: Self.start) == .handOff)
    }

    @Test func corruptDocumentMatchesNoField() {
        defaults.set(42, forKey: "catkeys.codeHandOff.document")
        defaults.set(Self.start, forKey: "catkeys.codeHandOff.date")
        #expect(handOff.decide(document: Self.field, now: Self.start + 30) == .quietPeriod)
        #expect(handOff.decide(document: Self.otherField, now: Self.start + 30 + 60) == .handOff)
    }
}
