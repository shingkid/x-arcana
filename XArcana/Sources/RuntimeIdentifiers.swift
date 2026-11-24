import Foundation

/// Keep these identifiers stable so installed controllers and head trackers can reconnect after updates.
enum RuntimeIdentifiers {
    static let controllerService = "_ember-wand._tcp"
    static let headService = "_ember-head._tcp"
}
