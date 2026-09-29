import Foundation

enum RatingClientError: Error, Equatable {
    case invalidURL
    case insecureURL
    case invalidResponse
    case httpStatus(Int)
    case invalidPayload
    case apiFailure(Int)
}

/// 虎扑评分树：比赛级取单局，单局级取选手与队伍分组。
struct RatingClient: Sendable {
    private static let host = "games.mobileapi.hupu.com"
    static let base = "https://games.mobileapi.hupu.com/1/8.2.99"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// 比赛级评分树：返回单局标签。
    func fetchStages(type: String, number: String) async throws -> [RatingStageRef] {
        let children = try await fetchTree(type: type, number: number).children
        return children.map {
            RatingStageRef(name: $0.name, bizType: $0.bizType, bizNo: $0.bizNo, targetCount: $0.subNodeCount)
        }
    }

    /// 比赛级评分树的直接子节点。
    func fetchTree(type: String, number: String) async throws -> (root: RatingTarget?, children: [RatingTarget]) {
        let data = try await treeData(type: type, number: number)
        return try Self.parseTree(data)
    }

    /// 比赛级或单局级的原始评分树响应。
    func treeData(type: String, number: String) async throws -> Data {
        try await request(path: "/bplcommentapi/bpl/score_tree/getCurAndSubNodeByBizKey", query: [
            URLQueryItem(name: "outBizType", value: type),
            URLQueryItem(name: "outBizNo", value: number),
            URLQueryItem(name: "relation", value: "CHILD"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "pageSize", value: "100")
        ])
    }

    /// 单局的队伍或话题分组列表。
    private func groupList(type: String, number: String) async throws -> Data {
        try await request(path: "/bplcommentapi/bpl/score_tree/getSubGroups", query: [
            URLQueryItem(name: "outBizType", value: type),
            URLQueryItem(name: "outBizNo", value: number)
        ])
    }

    /// 单个评分对象（用于刷新选手的均分、人数与我的评分）。
    func fetchTarget(type: String, number: String) async throws -> RatingTarget {
        let tree = try await fetchTree(type: type, number: number)
        guard let root = tree.root else { throw RatingClientError.invalidPayload }
        return root
    }

    /// 单局详情：标题、说明、直接评分对象，以及按队伍/话题分组后的对象。
    func fetchStageDetail(type: String, number: String) async throws -> StageDetail {
        async let treeRequest = treeData(type: type, number: number)
        async let groupsRequest = groupList(type: type, number: number)
        let tree = try Self.parseTree(try await treeRequest)
        let title = tree.root?.name ?? "单局详情"
        let rawGroups = (try? Self.parseGroups(try await groupsRequest)) ?? []
        let populated = await populate(rawGroups, stageName: title)
        return StageDetail(
            title: title,
            description: tree.root?.description,
            imageURL: tree.root?.imageURL,
            targets: tree.children.map { $0.with(stageName: title) },
            groups: populated
        )
    }

    private func populate(_ groups: [RatingGroup], stageName: String) async -> [RatingGroup] {
        guard !groups.isEmpty else { return [] }
        return await withTaskGroup(of: (Int, [RatingTarget]).self) { taskGroup in
            for (index, group) in groups.enumerated() {
                taskGroup.addTask {
                    let targets = (try? await groupTargets(nodeID: group.rootNodeID, stageName: stageName)) ?? []
                    return (index, targets)
                }
            }
            var loaded: [Int: [RatingTarget]] = [:]
            for await (index, targets) in taskGroup {
                loaded[index] = targets
            }
            return groups.enumerated().map { index, group in
                group.with(targets: loaded[index] ?? [])
            }
        }
    }

    private func groupTargets(nodeID: Int64, stageName: String) async throws -> [RatingTarget] {
        let data = try await request(path: "/bplcommentapi/bff/bpl/score_tree/groupAndSubNodes", query: [
            URLQueryItem(name: "nodeId", value: String(nodeID)),
            URLQueryItem(name: "queryType", value: "hot"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "pageSize", value: "100")
        ])
        return try Self.parseGroupTargets(data, stageName: stageName)
    }

    private func request(path: String, query: [URLQueryItem]) async throws -> Data {
        guard var components = URLComponents(string: Self.base + path) else { throw RatingClientError.invalidURL }
        components.queryItems = query
        guard let url = components.url else { throw RatingClientError.invalidURL }
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == Self.host else {
            throw RatingClientError.insecureURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Miaopu-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw RatingClientError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw RatingClientError.httpStatus(response.statusCode) }
        return data
    }

    // MARK: - 解析

    static func parseTree(_ data: Data) throws -> (root: RatingTarget?, children: [RatingTarget]) {
        let payload = try envelope(data)
        let root = payload["self"].flatMap { ($0 as? [String: Any])?["node"] as? [String: Any] }
            .flatMap { target(from: $0, wrapper: nil) }
        let rows = pageRows(payload)
        let children = rows.compactMap { entry -> RatingTarget? in
            guard let node = entry["node"] as? [String: Any] else { return nil }
            return target(from: node, wrapper: entry)
        }
        return (root, children)
    }

    static func parseGroupTargets(_ data: Data, stageName: String) throws -> [RatingTarget] {
        let payload = try envelope(data)
        let rows = (payload["nodePageResult"] as? [String: Any])?["data"] as? [Any] ?? []
        return rows.compactMap { raw -> RatingTarget? in
            guard let entry = raw as? [String: Any], let node = entry["node"] as? [String: Any] else { return nil }
            return target(from: node, wrapper: entry)?.with(stageName: stageName)
        }
    }

    static func parseGroups(_ data: Data) throws -> [RatingGroup] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = integer(root["code"]), code == 1 else {
            throw RatingClientError.invalidPayload
        }
        let rows = root["data"] as? [Any] ?? []
        let groups = rows.compactMap { raw -> RatingGroup? in
            guard let row = raw as? [String: Any], let name = string(row["groupName"]),
                  let rootNodeID = int64(row["rootNodeId"]) else { return nil }
            let attributes = row["attributes"] as? [String: Any]
            return RatingGroup(
                rootNodeID: rootNodeID,
                name: name,
                sort: integer(row["sort"]) ?? 0,
                logoURL: imageURL(attributes?["logo"]),
                teamID: string((attributes?["teamId"] as? [Any])?.first),
                childCount: integer(row["childCount"]) ?? 0,
                targets: []
            )
        }
        // 与安卓一致：趣评排在最前，其余按 sort 倒序。
        return groups.sorted { left, right in
            if left.isFun != right.isFun { return left.isFun }
            return left.sort > right.sort
        }
    }

    /// 比赛级响应里内嵌在单局下的选手，用于切换标签时立即显示内容。
    static func parseStageSeeds(_ data: Data) -> [String: [RatingTarget]] {
        guard let payload = try? envelope(data) else { return [:] }
        var result: [String: [RatingTarget]] = [:]
        for entry in pageRows(payload) {
            guard let node = entry["node"] as? [String: Any],
                  let stage = target(from: node, wrapper: entry) else { continue }
            result[stage.id] = nestedTargets(entry)
        }
        return result
    }

    /// 递归展开 `subNodes`，只保留可以评分或已有评分的对象。
    static func nestedTargets(_ entry: [String: Any]) -> [RatingTarget] {
        var found: [RatingTarget] = []
        var seen = Set<String>()
        func collect(_ raw: Any?) {
            guard let rows = raw as? [Any] else { return }
            for item in rows {
                guard let wrapper = item as? [String: Any] else { continue }
                if let node = wrapper["node"] as? [String: Any],
                   let target = target(from: node, wrapper: wrapper),
                   target.canScore || target.scoreCount > 0,
                   seen.insert(target.id).inserted {
                    found.append(target)
                }
                collect(wrapper["subNodes"])
            }
        }
        collect(entry["subNodes"])
        return found
    }

    private static func envelope(_ data: Data) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RatingClientError.invalidPayload
        }
        guard let code = integer(root["code"]) else { throw RatingClientError.invalidPayload }
        guard code == 1, (root["success"] as? Bool) == true else { throw RatingClientError.apiFailure(code) }
        guard let payload = root["data"] as? [String: Any] else { throw RatingClientError.invalidPayload }
        return payload
    }

    private static func pageRows(_ payload: [String: Any]) -> [[String: Any]] {
        let rows = (payload["pageResult"] as? [String: Any])?["data"] as? [Any] ?? []
        return rows.compactMap { $0 as? [String: Any] }
    }

    static func target(from node: [String: Any], wrapper: [String: Any]?) -> RatingTarget? {
        guard let bizType = string(node["bizType"]), let bizNo = string(node["bizId"]) else { return nil }
        let info = node["infoJson"] as? [String: Any]
        let labels = (info?["label"] as? [Any] ?? []).compactMap { entry -> String? in
            guard let row = entry as? [String: Any] else { return nil }
            return string(row["text"])
        }
        let directCount = integer(node["scorePersonCount"]) ?? 0
        let summedCount = integer(node["summedScorePersonCount"]) ?? 0
        let directComments = integer(node["commentCount"]) ?? 0
        let summedComments = integer(node["summedCommentCount"]) ?? 0
        var distribution: [Int: Int] = [:]
        if let raw = node["scoreDistribution"] as? [String: Any] {
            for score in stride(from: 2, through: 10, by: 2) {
                distribution[score] = integer(raw[String(score)]) ?? 0
            }
        }
        return RatingTarget(
            nodeID: int64(wrapper?["nodeId"]) ?? int64(node["nodeId"]) ?? int64((node["scoreItemNodeId"] as? [Any])?.first),
            bizType: bizType,
            bizNo: bizNo,
            name: string(node["name"]) ?? "评分对象",
            description: firstString(info?["desc"]) ?? labels.first,
            stageName: nil,
            labels: labels,
            imageURL: imageURL((node["image"] as? [Any])?.first),
            championURL: imageURL(firstString(info?["auxiliaryPic"])),
            scoreAverage: double(node["scoreAvg"]) ?? 0,
            scoreCount: directCount == 0 ? summedCount : directCount,
            commentCount: max(directComments, summedComments),
            userScore: integer(node["userScore"]) ?? 0,
            canScore: node["canScore"] as? Bool ?? false,
            canComment: node["canComment"] as? Bool ?? false,
            hotComment: firstString(node["hottestComments"]),
            scoreDistribution: distribution,
            category: firstString(info?["type"]),
            teamID: firstString(info?["teamId"]),
            subNodeCount: integer(wrapper?["subNodeCount"]) ?? 0
        )
    }

    static func string(_ raw: Any?) -> String? {
        guard let raw, !(raw is NSNull) else { return nil }
        if let value = raw as? String { return value.isEmpty ? nil : value }
        if let value = raw as? NSNumber { return value.stringValue }
        return nil
    }

    static func firstString(_ raw: Any?) -> String? {
        guard let rows = raw as? [Any] else { return string(raw) }
        for row in rows {
            if let value = string(row) { return value }
        }
        return nil
    }

    static func integer(_ raw: Any?) -> Int? {
        guard let raw, !(raw is NSNull) else { return nil }
        if let value = raw as? Int { return value }
        if let value = raw as? NSNumber { return value.intValue }
        if let value = raw as? String { return Int(value) }
        return nil
    }

    static func int64(_ raw: Any?) -> Int64? {
        guard let raw, !(raw is NSNull) else { return nil }
        if let value = raw as? Int64 { return value }
        if let value = raw as? NSNumber { return value.int64Value }
        if let value = raw as? String { return Int64(value) }
        return nil
    }

    static func double(_ raw: Any?) -> Double? {
        guard let raw, !(raw is NSNull) else { return nil }
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = raw as? String { return Double(value) }
        return nil
    }

    static func imageURL(_ raw: Any?) -> URL? {
        guard let value = string(raw), var parts = URLComponents(string: value),
              let host = parts.host?.lowercased(),
              host == "hoopchina.com.cn" || host.hasSuffix(".hoopchina.com.cn"),
              parts.scheme == "https" || parts.scheme == "http" else { return nil }
        parts.scheme = "https"
        return parts.url
    }
}
