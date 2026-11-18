import Testing
import Foundation
import AppKit
@testable import Olaz

/// The bridge must reproduce Node's crypto byte-for-byte: the official renderer
/// encrypts `zcid` and request params through `$znode.crypto`. Expected values
/// were produced by Node 26 (`crypto.createCipheriv` & co.).
@MainActor
@Suite struct CryptoBridgeParity {
    private func call(_ bridge: ZaloBridge, _ path: String, _ args: [Any]) throws -> Any? {
        let body = try JSONSerialization.data(withJSONObject: ["path": path, "args": args.map { ZaloBridge.toJS($0) }])
        let response = try JSONSerialization.jsonObject(with: bridge.handleSyncRequest(body)) as! [String: Any]
        if let error = response["error"] as? String { throw ZaloBridge.BridgeError(message: error) }
        return response["value"].map(ZaloBridge.fromJS)
    }

    private func makeBridge() -> ZaloBridge {
        let bridge = ZaloBridge()
        CryptoBridge.install(on: bridge)
        return bridge
    }

    @Test func zcidEncryptMatchesNode() throws {
        let out = try call(makeBridge(), "$znode.crypto.encrypt", [
            "23,abc-imei,1792963077777", "aes-256-cbc", "3FC4F0D2AB50057BCE0D90D9187A22B1", NSNull(),
            ["key": "utf-8", "input": "utf-8", "output": "hex"],
        ])
        #expect(out as? String == "a1a69db6a344da4d883865c637f979495dd86112a4534347b462259bfdeb641b")
    }

    @Test func paramsRoundTripBase64() throws {
        let bridge = makeBridge()
        let key = "DE71B7D4C57C0749158CB90D5E431AE3"
        let encrypted = try call(bridge, "$znode.crypto.encrypt", [
            "{\"language\":\"vi\"}", "aes-256-cbc", key, NSNull(), ["key": "utf-8", "input": "utf-8", "output": "base64"],
        ])
        #expect(encrypted as? String == "V5p1S6tTwaE91W8UDCagn9vVP9wUQ3QzA04wG7xh+5E=")
        let decrypted = try call(bridge, "$znode.crypto.decrypt", [
            encrypted!, "aes-256-cbc", key, NSNull(), ["key": "utf-8", "input": "base64", "output": "utf-8"],
        ])
        #expect(decrypted as? String == "{\"language\":\"vi\"}")
    }

    @Test func streamingCTRAndGCM() throws {
        let bridge = makeBridge()
        let ctr = try call(bridge, "$znode.crypto.__cipherCreate", ["cipher", "aes-128-ctr", Data(repeating: 7, count: 16), Data(repeating: 1, count: 16)]) as! Int
        let ctrOut = try call(bridge, "$znode.crypto.__cipherUpdate", [ctr, "hello zalo ctr mode!", "utf8", "hex"]) as? String
        #expect(ctrOut == "324a84ef5fc3a21b11456b948b319aab1c6e924d")

        let gcm = try call(bridge, "$znode.crypto.__cipherCreate", ["cipher", "aes-256-gcm", Data(repeating: 3, count: 32), Data(repeating: 9, count: 12)]) as! Int
        _ = try call(bridge, "$znode.crypto.__cipherUpdate", [gcm, "gcm payload", "utf8", NSNull()])
        let sealed = try call(bridge, "$znode.crypto.__cipherFinal", [gcm, "hex"]) as? String
        #expect(sealed == "636b00fbfe1c3505e56f0c")
        let tag = try call(bridge, "$znode.crypto.__cipherOption", [gcm, "getAuthTag"]) as? Data
        #expect(tag?.map { String(format: "%02x", $0) }.joined() == "377ee9d6cfa423566629c0cfbb8eb885")
    }

    @Test func hashes() throws {
        let bridge = makeBridge()
        let h = try call(bridge, "$znode.crypto.__hashCreate", ["md5"]) as! Int
        _ = try call(bridge, "$znode.crypto.__hashUpdate", [h, "841630ae41f", NSNull()])
        #expect(try call(bridge, "$znode.crypto.__hashDigest", [h, "hex"]) as? String == "d9e97c18b27cd54e969268d9b39e8680")
        #expect(try call(bridge, "$znode.crypto.hash", ["zalo", "sha256", NSNull(), "base64"]) as? String
                == "PpYUHCFwTpavYlfqQcD8aQzgUEyFKdxCTciyRbY0PA8=")
    }

    @Test func badDecryptThrows() {
        #expect(throws: (any Error).self) {
            try call(makeBridge(), "$znode.crypto.decrypt", [
                "AAAAAAAAAAAAAAAAAAAAAA==", "aes-256-cbc", "DE71B7D4C57C0749158CB90D5E431AE3", NSNull(),
                ["key": "utf-8", "input": "base64", "output": "utf-8"],
            ])
        }
    }
}

@Suite struct AsarReading {
    /// Builds a minimal asar: header pickle + two files.
    private func makeArchive() throws -> URL {
        let files: [(String, Data)] = [("pc-dist/login.html", Data("<html>hi</html>".utf8)), ("pc-dist/lazy/a.js", Data("1+1".utf8))]
        var offset = 0
        var tree: [String: Any] = [:]
        var payload = Data()
        for (path, data) in files {
            let parts = path.split(separator: "/").map(String.init)
            func insert(_ node: inout [String: Any], _ rest: ArraySlice<String>) {
                var files = node["files"] as? [String: Any] ?? [:]
                if rest.count == 1 {
                    files[rest.first!] = ["size": data.count, "offset": String(offset)]
                } else {
                    var child = files[rest.first!] as? [String: Any] ?? [:]
                    insert(&child, rest.dropFirst())
                    files[rest.first!] = child
                }
                node["files"] = files
            }
            insert(&tree, parts[...])
            payload.append(data)
            offset += data.count
        }
        let json = try JSONSerialization.data(withJSONObject: tree)
        func u32(_ v: Int) -> Data { withUnsafeBytes(of: UInt32(v).littleEndian) { Data($0) } }
        let padded = (json.count + 3) & ~3
        let headerPickle = u32(padded + 4) + u32(json.count) + json + Data(count: padded - json.count)
        let archive = u32(4) + u32(headerPickle.count) + headerPickle + payload
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("olaz-test-\(UUID()).asar")
        try archive.write(to: url)
        return url
    }

    @Test func readsFilesFromArchive() throws {
        let asar = try AsarArchive(url: try makeArchive())
        #expect(asar.read("pc-dist/login.html").map { String(decoding: $0, as: UTF8.self) } == "<html>hi</html>")
        #expect(asar.read("/pc-dist/lazy/a.js").map { String(decoding: $0, as: UTF8.self) } == "1+1")
        #expect(asar.read("pc-dist/missing.js") == nil)
        #expect(asar.paths(withPrefix: "pc-dist/lazy").count == 1)
    }

    @Test func installedZaloIsReadableWhenPresent() throws {
        guard FileManager.default.fileExists(atPath: OfficialZaloInstall.defaultAppURL.path) else { return }
        let info = try OfficialZaloInstall.locate()
        #expect(info.asar.contains("pc-dist/login.html"))
        #expect(info.asar.contains("pc-dist/index.html"))
    }
}

@MainActor
@Suite struct SessionCookies {
    /// The realtime socket (`wss://wsN-msg.chat.zalo.me`) must receive `zpw_sek`,
    /// as Electron's domain cookies did; a host-only cookie silently breaks it.
    @Test func appCookieReachesRealtimeAndAPIHosts() {
        let storage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: "olaz.tests.\(UUID())")
        for domain in ZaloMainProcess.sessionCookieDomains {
            ZaloMainProcess.setCookie(name: "zpw_sek", value: "test", domain: domain, days: 1, httpOnly: true, storage: storage)
        }
        for host in ["https://ws5-msg.chat.zalo.me/", "https://chat.zalo.me/", "https://wpa.zaloapp.com/", "https://tt-profile-wpa.zaloapp.com/"] {
            let names = storage.cookies(for: URL(string: host)!)?.map(\.name) ?? []
            #expect(names.contains("zpw_sek"), "missing zpw_sek for \(host)")
        }
    }
}

/// Ảnh QR đăng nhập trang gửi sang: QR1 từ máy chủ là PNG base64, còn QR2 trang tự sinh (`T()` trong
/// login-startup) là SVG percent-encode. Đọc sai QR2 thì màn giữ QR1 đã dùng và điện thoại báo "Mã QR không hợp lệ".
@MainActor
@Suite struct LoginQRDataURL {
    @Test func base64PNGDecodes() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        #expect(ZaloEngine.decodeDataURL("data:image/png;base64," + png.base64EncodedString()) == png)
    }

    @Test func selfGeneratedSVGDecodesToAnImage() throws {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" version="1.1" fill="white" width="480" height="480" viewBox="0 0 480 480"><rect width="100%" height="100%" fill="white"/><rect style="fill:black;" x="48" y="48" width="48" height="48"/></svg>"#
        // Mã hoá như `encodeURIComponent` của JS.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.!~*'()"))
        let url = "data:image/svg+xml;utf8," + svg.addingPercentEncoding(withAllowedCharacters: allowed)!
        let data = try #require(ZaloEngine.decodeDataURL(url))
        #expect(String(decoding: data, as: UTF8.self) == svg)
        #expect(NSImage(data: data)?.size == CGSize(width: 480, height: 480))
    }

    @Test func percentEncodedBytesAndUppercaseScheme() {
        #expect(ZaloEngine.decodeDataURL("data:application/octet-stream,%00%FFa") == Data([0x00, 0xFF, 0x61]))
        #expect(ZaloEngine.decodeDataURL("DATA:text/plain;BASE64,AAE=") == Data([0x00, 0x01]))
        #expect(ZaloEngine.decodeDataURL("data:text/plain,%G1") == nil)
    }

    @Test func notADataURL() {
        #expect(ZaloEngine.decodeDataURL("https://example.com/qr.png") == nil)
    }
}
