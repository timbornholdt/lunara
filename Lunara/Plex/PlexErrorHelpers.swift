import Foundation

enum PlexErrorHelpers {
    static func isUnauthorized(_ error: Error) -> Bool {
        (error as? PlexHTTPError)?.isUnauthorized == true
    }
}
