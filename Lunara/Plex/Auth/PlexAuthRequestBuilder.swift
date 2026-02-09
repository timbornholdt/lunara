import Foundation

struct PlexAuthRequestBuilder {
    let baseURL: URL
    let configuration: PlexClientConfiguration

    func makeSignInRequest(
        login: String,
        password: String,
        verificationCode: String?,
        rememberMe: Bool
    ) throws -> URLRequest {
        let url = baseURL.appendingPathComponent("users/signin")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        var bodyParameters: [String: String] = [
            "login": login,
            "password": password,
            "rememberMe": rememberMe ? "1" : "0"
        ]
        if let verificationCode {
            bodyParameters["verificationCode"] = verificationCode
        }

        request.httpBody = PlexURLEncodedForm.encode(bodyParameters)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        applyHeaders(to: &request)
        return request
    }

    private func applyHeaders(to request: inout URLRequest) {
        for (key, value) in configuration.defaultHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }
}
