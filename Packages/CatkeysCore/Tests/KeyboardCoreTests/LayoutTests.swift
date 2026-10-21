import Foundation
import Testing
import KeyboardCore

@Test func lettersPageMatchesDesign() throws {
    let set = try LayoutSet.bundled()
    let p = try #require(set.page(set.lettersPageID))
    #expect(p.rows.map(\.kind) == [.number, .keys, .keys, .keys])
    #expect(p.rows[0].keys.map(\.label) == ["1","2","3","4","5","6","7","8","9","0"])
    #expect(p.rows[1].keys.map(\.label) == ["q","w","e","r","t","y","u","i","o","p"])
    #expect(p.rows[1].keys.map(\.cornerHint) == ["%","\\","|","=","[","]","<",">","{","}"])
    #expect(p.rows[2].keys.map(\.cornerHint) == ["@","#","₹","_","&","-","+","(",")"])
    #expect(p.rows[3].keys.map(\.cornerHint) == [nil,"*","\"","'",":",";","!","?",nil])
    #expect(p.rows[3].keys.first?.action == .shift && p.rows[3].keys.last?.action == .backspace)
    #expect(p.rows[2].keys[2].longPress == ["₹","$","€"])
    #expect(p.bottomRow(.standard).map(\.action) == [.switchPage(.named("symbols-1")), .emoji, .character, .space, .character, .returnKey])
    #expect(p.bottomRow(.standard)[4].longPress == [".","?","!","…",":","/"])
}

@Test func symbolsPagesMatchDesign() throws {
    let set = try LayoutSet.bundled()
    let s1 = try #require(set.page("symbols-1")), s2 = try #require(set.page("symbols-2"))
    #expect(s1.rows[1].keys.map(\.label) == ["@","#","₹","$","_","&","-","+","(",")"])
    #expect(s1.rows[2].keys.map(\.label) == ["*","\"","'",":",";","!","?","/","%","="])
    #expect(s1.rows[3].keys.map(\.label) == ["1/2","<",">","[","]","{","}","|","⌫"])
    #expect(s2.rows[1].keys.map(\.label) == ["~","`","\\","^","•","°","…","§","¶","©"])
    #expect(s2.rows[2].keys.map(\.label) == ["€","£","¥","¢","×","÷","√","π","∞","™"])
    #expect(s2.rows[3].keys.map(\.label) == ["2/2","®","✓","«","»","¿","¡","‰","⌫"])
    #expect(s1.rows[0] == set.page(set.lettersPageID)!.rows[0])
    #expect(s1.bottomRow(.standard).first?.action == .switchPage(.letters))
    #expect(s1.rows[1].keys.allSatisfy { $0.cornerHint == nil })
}

@Test func fieldVariants() throws {
    let p = try #require(try LayoutSet.bundled().page("latin-qwerty"))
    #expect(p.bottomRow(.email).map(\.output).contains("@"))
    #expect(p.bottomRow(.url).map(\.output).contains("/") && p.bottomRow(.url).map(\.output).contains(".com"))
}

@Test func globeKeyComesFromTheIndex() throws {
    let globe = try #require(try LayoutSet.bundled().globeKey)
    #expect(globe.label == "🌐" && globe.action == .globe && globe.width == 1)
}

@Test func decodingDefaults() throws {
    let k = try JSONDecoder().decode(KeySpec.self, from: Data(#"{"label":"a","extra":1}"#.utf8))
    #expect(k.output == "a" && k.width == 1 && k.longPress.isEmpty && k.action == .character)
}
