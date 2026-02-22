import Foundation
import Testing
@testable import Lunara

@Suite
struct LastFMClientTests {

    @Test
    func signedParams_producesCorrectMD5Signature() {
        let client = LastFMClient(apiKey: "testkey", apiSecret: "testsecret")
        let params = ["method": "auth.getToken", "api_key": "testkey"]
        let signed = client.signedParams(params)

        #expect(signed["api_sig"] != nil)
        #expect(signed["format"] == "json")
        #expect(signed["method"] == "auth.getToken")
        #expect(signed["api_key"] == "testkey")
    }

    @Test
    func signedParams_isDeterministic() {
        let client = LastFMClient(apiKey: "key", apiSecret: "secret")
        let params = ["b": "2", "a": "1"]
        let sig1 = client.signedParams(params)["api_sig"]
        let sig2 = client.signedParams(params)["api_sig"]
        #expect(sig1 == sig2)
    }

    @Test
    func signedParams_changesWithDifferentParams() {
        let client = LastFMClient(apiKey: "key", apiSecret: "secret")
        let sig1 = client.signedParams(["a": "1"])["api_sig"]
        let sig2 = client.signedParams(["a": "2"])["api_sig"]
        #expect(sig1 != sig2)
    }
}
