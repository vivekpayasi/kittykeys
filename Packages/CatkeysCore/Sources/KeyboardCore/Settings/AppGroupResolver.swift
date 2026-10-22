import Foundation

/// Finds the App Group this install can actually use.
///
/// Sideloading tools that re-sign with a free Apple ID (SideStore, AltStore) rewrite bundle IDs and rename
/// App Groups, for example `group.com.vivek.catkeys` to `group.com.vivek.catkeys.ABCDE12345`, so the
/// canonical id from Info.plist may not be the group this install was granted. The granted groups are
/// listed in the bundle's `embedded.mobileprovision`; each bundle (the app, the keyboard) carries its own.
/// Pattern from the Sahaja app's `AppGroup`.
public enum AppGroupResolver {
    private static let groupsKey = "com.apple.security.application-groups"

    /// The App Group usable in this process, or nil: the canonical id if its container exists,
    /// otherwise the first group from this bundle's embedded.mobileprovision whose container exists.
    /// nil when `canonical` is nil. The profile is read only when the canonical id has no container.
    public static func resolve(canonical: String?, bundle: Bundle = .main,
                               containerExists: (String) -> Bool = { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }) -> String? {
        guard let canonical else { return nil }
        if containerExists(canonical) { return canonical }
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return groups(fromProvisioningProfile: data, canonical: canonical)
            .first { $0 != canonical && containerExists($0) }
    }

    /// `com.apple.security.application-groups` from a raw .mobileprovision (CMS envelope around an XML plist);
    /// groups containing the canonical id's last component come first.
    public static func groups(fromProvisioningProfile data: Data, canonical: String?) -> [String] {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements[groupsKey] as? [Any]
        else { return [] }
        let ids = groups.compactMap { $0 as? String }
        // "catkeys" for "group.com.vivek.catkeys": SideStore keeps it when it renames the group.
        guard let name = canonical?.split(separator: ".").last else { return ids }
        let renamed = ids.filter { $0.contains(name) }
        return renamed + ids.filter { !$0.contains(name) }
    }
}
