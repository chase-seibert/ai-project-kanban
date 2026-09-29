import Foundation

@main struct VerifyCodex {
    @MainActor static func main() async throws {
        let connection = CodexConnection()
        let path = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        try await connection.connect(executable: path)
        let account = try await connection.call("account/read", ["refreshToken": false])
        print("initialize + initialized: PASS")
        print("account/read: PASS; signed in = \(account["account"] is [String: Any])")
        var cursor: String?
        var seen = Set<String>()
        var models: [CodexModelOption] = []
        for _ in 0..<20 {
            var params: [String: Any] = ["limit": 100, "includeHidden": false]
            if let cursor { params["cursor"] = cursor }
            let result = try await connection.call("model/list", params)
            guard let data = result["data"] as? [[String: Any]] else {
                throw BoardError.invalid("model/list returned no model data")
            }
            models.append(contentsOf: data.compactMap { entry in
                guard let id = entry["id"] as? String,
                      let displayName = entry["displayName"] as? String else { return nil }
                let efforts = (entry["supportedReasoningEfforts"] as? [[String: Any]] ?? [])
                    .compactMap { $0["reasoningEffort"] as? String }
                return CodexModelOption(
                    id: id, displayName: displayName,
                    hidden: entry["hidden"] as? Bool ?? false,
                    reasoningEfforts: efforts)
            })
            guard let next = result["nextCursor"] as? String, !next.isEmpty else { break }
            guard seen.insert(next).inserted else {
                throw BoardError.invalid("model/list repeated a page cursor")
            }
            cursor = next
        }
        let selection = CodexModelConfiguration()
        let latest = try CodexModelResolver.resolve(selection, scope: .global, catalog: models)
        print("model/list: PASS; \(models.count) visible models; default resolves to \(latest.modelID) · \(latest.effort)")
        connection.close()
        print("No turn was started; model usage was not incurred.")
    }
}
