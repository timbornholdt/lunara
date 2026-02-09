import Foundation
import Testing
@testable import Lunara

struct PlexSignInDecodingTests {
    @Test func decodesAuthToken() throws {
        let json = """
        {
          "user": {
            "authToken": "token-123"
          }
        }
        """

        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(PlexSignInResponse.self, from: data)
        #expect(response.user.authToken == "token-123")
    }
}
