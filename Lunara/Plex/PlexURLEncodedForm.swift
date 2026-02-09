import Foundation

enum PlexURLEncodedForm {
    static func encode(_ parameters: [String: String]) -> Data {
        let pairs = parameters
            .map { key, value in
                "\(escape(key))=\(escape(value))"
            }
            .joined(separator: "&")
        return Data(pairs.utf8)
    }

    private static func escape(_ string: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}
