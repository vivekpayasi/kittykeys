import Foundation
import Testing
import KeyboardCore

/// Web-address and email fields' bottom rows, and the currency the "d" key and the 123 page offer.
@MainActor struct WebFieldTests {
    func labels(_ k: Harness) -> [String] { k.controller.frames.map(\.key.label) }

    func spaceWidth(_ k: Harness) throws -> Double {
        try #require(k.controller.frames.first { $0.key.action == .space }).rect.width
    }

    /// Without the .com key, the space bar is as wide as in any text field, on the letters and on the 123 pages.
    @Test func webFieldsHaveNoDotComKeyByDefault() throws {
        let k = try Harness()
        let textSpace = try spaceWidth(k)
        k.controller.fieldDidChange(FieldTraits(kind: .url))
        for page in ["latin-qwerty", "symbols-1", "symbols-2"] {
            while k.controller.state.pageID != page { try k.tap(k.controller.state.pageID == "latin-qwerty" ? "123" : "1/2") }
            #expect(labels(k).contains("/") && !labels(k).contains(".com"), "\(page)")
            #expect(try spaceWidth(k) == textSpace, "\(page)")
        }
    }

    @Test func theDotComKeyShowsOnEveryPage() throws {
        var settings = KeyboardSettings()
        settings.showDotComKey = true
        let k = try Harness(settings: settings)
        k.controller.fieldDidChange(FieldTraits(kind: .url))
        for page in ["latin-qwerty", "symbols-1", "symbols-2"] {
            while k.controller.state.pageID != page { try k.tap(k.controller.state.pageID == "latin-qwerty" ? "123" : "1/2") }
            #expect(labels(k).contains(".com"), "\(page)")
        }
    }

    /// Domains are wider than a symbol, so "."'s popup has wider cells, which still fit on the keyboard.
    @Test func domainPopupHasWideCellsThatFit() throws {
        let k = try Harness()
        k.controller.fieldDidChange(FieldTraits(kind: .url))
        try k.down(".")
        k.wait(0.5)
        let popup = try #require(k.controller.state.alternates)
        #expect(popup.cellWidth == 36 * 1.6)
        #expect(popup.originX >= 0 && popup.originX + Double(popup.options.count) * popup.cellWidth <= 390)
    }

    /// Near the right edge the domains run leftward, .com under the finger; one wide cell to the left is .in.
    @Test func slidingOneWideCellPicksTheNextDomain() throws {
        let k = try Harness("example")
        k.controller.fieldDidChange(FieldTraits(kind: .url, autoCap: .none))
        let p = try k.down(".")
        k.wait(0.5)
        let cell = try #require(k.controller.state.alternates).cellWidth
        let left = Point(x: p.x - cell, y: p.y)
        k.move(to: left)
        k.up(at: left)
        #expect(k.doc.text == "example.in")
    }

    @Test func symbolPopupsKeepNarrowCells() throws {
        let k = try Harness()
        try k.down("d")
        k.wait(0.5)
        #expect(try #require(k.controller.state.alternates).cellWidth == 36)
    }

    /// Settings load as the keyboard appears; changing both at once still lays the keys out again.
    @Test func changingBothSettingsLaysOutTheKeysAgain() throws {
        let k = try Harness()
        k.controller.fieldDidChange(FieldTraits(kind: .url))
        var settings = k.controller.settings
        settings.showDotComKey = true
        settings.currency = "£"
        k.controller.settings = settings
        #expect(labels(k).contains(".com"))
        #expect(try k.key("d").key.cornerHint == "£")
    }

    /// The .com setting changes only the bottom row: the page stays, and so does a text field's row.
    @Test func theDotComSettingKeepsThePage() throws {
        let k = try Harness()
        try k.tap("123")
        var settings = k.controller.settings
        settings.showDotComKey = true
        k.controller.settings = settings
        #expect(k.controller.state.pageID == "symbols-1" && !labels(k).contains(".com"))
    }

    @Test func theSettingBringsBackTheDotComKey() throws {
        var settings = KeyboardSettings()
        settings.showDotComKey = true
        let k = try Harness(settings: settings)
        k.controller.fieldDidChange(FieldTraits(kind: .url))
        #expect(labels(k).contains(".com"))
    }

    @Test(arguments: [FieldKind.url, .email])
    func holdingPeriodOffersDomains(_ kind: FieldKind) throws {
        let k = try Harness()
        k.controller.fieldDidChange(FieldTraits(kind: kind))
        let period = try k.key(".").key
        #expect(Array(period.longPress.prefix(2)) == [".com", ".in"])
    }

    @Test func holdingPeriodInTextFieldsKeepsPunctuation() throws {
        let k = try Harness()
        #expect(try k.key(".").key.longPress.first == ".")
    }

    /// The first option is preselected, so a hold and a lift type ".com".
    @Test func holdAndLiftOnPeriodTypesDotCom() throws {
        let k = try Harness("example")
        k.controller.fieldDidChange(FieldTraits(kind: .url, autoCap: .none))
        let p = try k.down(".")
        k.wait(0.5)
        k.up(at: p)
        #expect(k.doc.text == "example.com")
    }
}

struct CurrencyOrderTests {
    static let all = ["$", "€", "£", "¥", "₹", "₩"]

    @Test func automaticPutsTheRegionsCurrencyFirst() {
        #expect(CurrencyOrder.ordered(choice: "", region: "₹", all: Self.all) == ["₹", "$", "€", "£", "¥", "₩"])
    }

    @Test func aChoiceComesFirst() {
        #expect(CurrencyOrder.ordered(choice: "£", region: "₹", all: Self.all) == ["£", "$", "€", "¥", "₹", "₩"])
    }

    /// A region currency the list lacks, such as "CHF", and a choice not in the list, both leave the list's order.
    @Test func unknownCurrenciesKeepTheListsOrder() {
        #expect(CurrencyOrder.ordered(choice: "", region: "CHF", all: Self.all) == Self.all)
        #expect(CurrencyOrder.ordered(choice: "X", region: nil, all: Self.all) == Self.all)
    }

    /// The region comes as a currency code, such as INR, since symbols vary: Japan's is a full-width ￥.
    @Test func regionCodesNameTheirCurrencies() throws {
        let set = try LayoutSet.bundled()
        #expect(set.currencySymbol(forCode: "INR") == "₹" && set.currencySymbol(forCode: "JPY") == "¥")
        #expect(set.currencySymbol(forCode: "AUD") == "$" && set.currencySymbol(forCode: "EUR") == "€")
        #expect(set.currencySymbol(forCode: "XYZ") == nil && set.currencySymbol(forCode: nil) == nil)
    }

    @Test func theLayoutListsCurrencies() throws {
        let currencies = try LayoutSet.bundled().currencies
        #expect(currencies.count >= 5 && Set(currencies).count == currencies.count)
        #expect(currencies.prefix(5) == ["$", "€", "£", "¥", "₹"])
    }
}

@MainActor struct CurrencyKeyTests {
    func harness(choice: String = "", region: String? = "₹") throws -> Harness {
        var settings = KeyboardSettings()
        settings.currency = choice
        let k = try Harness(settings: settings)
        k.controller.regionCurrency = region
        return k
    }

    @Test func dOffersTheRegionsCurrencyFirst() throws {
        let k = try harness()
        let d = try k.key("d").key
        #expect(d.longPress == ["₹", "$", "€", "£", "¥"])
        #expect(d.cornerHint == "₹")
    }

    @Test func aChosenCurrencyLeadsOnDAndTheSymbolsPage() throws {
        let k = try harness(choice: "€")
        #expect(try k.key("d").key.longPress == ["€", "$", "£", "¥", "₹"])
        try k.tap("123")
        let labels = k.controller.frames.map(\.key.label)
        #expect(labels.contains("€") && labels.contains("$") && !labels.contains("₹"))
    }

    @Test func changingTheSettingLaysOutTheKeysAgain() throws {
        let k = try harness()
        k.controller.settings.currency = "£"
        #expect(try k.key("d").key.cornerHint == "£")
    }

    /// Every page and bottom row fills its placeholders. ("{" and "}" themselves are symbol keys.)
    @Test func everyRowFillsItsPlaceholders() throws {
        let set = try LayoutSet.bundled()
        func isPlaceholder(_ text: String) -> Bool { text.hasPrefix("{currenc") }
        for id in ["latin-qwerty", "symbols-1", "symbols-2"] {
            let page = try #require(set.page(id, currencies: set.currencies))
            let keys = page.rows.flatMap(\.keys) + BottomVariant.allCases.flatMap { page.bottomRow($0) }
            for key in keys {
                #expect(!isPlaceholder(key.label) && !key.longPress.contains(where: isPlaceholder), "\(id): \(key.label)")
            }
        }
    }

    /// No placeholder is ever shown or typed. ("{" and "}" themselves are symbol keys.)
    @Test func noPlaceholderReachesTheKeys() throws {
        let k = try harness()
        func isPlaceholder(_ text: String) -> Bool { text.hasPrefix("{currenc") }
        for page in ["latin-qwerty", "symbols-1", "symbols-2"] {
            while k.controller.state.pageID != page { try k.tap(k.controller.state.pageID == "latin-qwerty" ? "123" : "1/2") }
            for frame in k.controller.frames {
                #expect(!isPlaceholder(frame.key.label) && !isPlaceholder(frame.key.output), "\(page): \(frame.key.label)")
                #expect(!frame.key.longPress.contains(where: isPlaceholder), "\(page): \(frame.key.label)")
            }
        }
    }
}
