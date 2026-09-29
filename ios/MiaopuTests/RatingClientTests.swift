import XCTest
@testable import Miaopu

final class RatingClientTests: XCTestCase {
    private let treeJSON = #"""
    {"code":1,"success":true,"data":{
      "self":{"node":{"name":"LGD 1-2 TT","bizType":"lol_match","bizId":"3715","image":["https://i10.hoopchina.com.cn/match.png"],"scoreAvg":0,"scorePersonCount":0,"summedScorePersonCount":9257,"commentCount":0,"infoJson":{"desc":["比赛日期：2026年08月06日"]}}},
      "pageResult":{"data":[
        {"nodeId":18496335,"subNodeCount":14,"node":{"name":"第3局","bizType":"lol_bo","bizId":"6720","scoreAvg":0,"scorePersonCount":0,"summedScorePersonCount":3984,"commentCount":0},"subNodes":[
          {"nodeId":18497348,"node":{"name":"Crisp","bizType":"lol_item","bizId":"72918","scoreAvg":3.3,"scorePersonCount":774,"commentCount":223,"userScore":0,"canScore":true,"canComment":true,"scoreDistribution":{"2":100,"10":50},"hottestComments":["玩得像我玩大乱斗"],"image":["http://i3.hoopchina.com.cn/player.png"],"infoJson":{"desc":["K/D/A:0/4/4"],"type":["player"],"teamId":["4"],"auxiliaryPic":["https://p1.hoopchina.com.cn/champion.png"],"label":[{"text":"LGD"}]}}},
          {"nodeId":18497349,"node":{"name":"Couch","bizType":"lol_item","bizId":"72919","scoreAvg":0,"scorePersonCount":0,"commentCount":0,"canScore":false,"canComment":false}}
        ]}
      ]}}}
    """#

    func testParsesMatchTreeAndSeededStageTargets() throws {
        let tree = try RatingClient.parseTree(Data(treeJSON.utf8))
        XCTAssertEqual(tree.root?.name, "LGD 1-2 TT")
        XCTAssertEqual(tree.root?.scoreCount, 9257)
        XCTAssertEqual(tree.root?.imageURL?.absoluteString, "https://i10.hoopchina.com.cn/match.png")
        XCTAssertEqual(tree.children.count, 1)
        XCTAssertEqual(tree.children[0].name, "第3局")
        XCTAssertEqual(tree.children[0].subNodeCount, 14)
        XCTAssertEqual(tree.children[0].id, "lol_bo:6720")

        let seeds = RatingClient.parseStageSeeds(Data(treeJSON.utf8))
        let players = try XCTUnwrap(seeds["lol_bo:6720"])
        XCTAssertEqual(players.count, 1, "只有可评分或已有评分的对象会进入单局列表")
        let player = players[0]
        XCTAssertEqual(player.name, "Crisp")
        XCTAssertEqual(player.id, "lol_item:72918")
        XCTAssertEqual(player.scoreCount, 774)
        XCTAssertEqual(player.commentCount, 223)
        XCTAssertEqual(player.description, "K/D/A:0/4/4")
        XCTAssertEqual(player.labels, ["LGD"])
        XCTAssertEqual(player.category, "player")
        XCTAssertEqual(player.teamID, "4")
        XCTAssertTrue(player.canScore)
        XCTAssertEqual(player.scoreDistribution[2], 100)
        XCTAssertEqual(player.scoreDistribution[4], 0)
        XCTAssertEqual(player.championURL?.absoluteString, "https://p1.hoopchina.com.cn/champion.png")
        XCTAssertEqual(player.imageURL?.absoluteString, "https://i3.hoopchina.com.cn/player.png")
        XCTAssertEqual(player.hotComment, "玩得像我玩大乱斗")
    }

    func testParsesGroupsWithFunFirstThenSortDescending() throws {
        let json = #"{"code":1,"success":true,"data":[{"groupName":"TT","rootNodeId":18497371,"sort":2,"childCount":7,"attributes":{"logo":"https://i5.hoopchina.com.cn/tt.png","teamId":["438"]}},{"groupName":"趣评","rootNodeId":9,"sort":5,"childCount":2},{"groupName":"LGD","rootNodeId":18497362,"sort":1,"childCount":7}]}"#
        let groups = try RatingClient.parseGroups(Data(json.utf8))
        XCTAssertEqual(groups.map(\.name), ["趣评", "TT", "LGD"])
        XCTAssertTrue(groups[0].isFun)
        XCTAssertEqual(groups[1].teamID, "438")
        XCTAssertEqual(groups[1].logoURL?.absoluteString, "https://i5.hoopchina.com.cn/tt.png")
    }

    func testParsesGroupTargetsWithStageName() throws {
        let json = #"{"code":1,"success":true,"data":{"nodePageResult":{"data":[{"nodeId":5,"node":{"name":"Player","bizType":"lol_item","bizId":"9","scoreAvg":8.2,"scorePersonCount":12,"commentCount":1,"canScore":true}}]}}}"#
        let targets = try RatingClient.parseGroupTargets(Data(json.utf8), stageName: "第3局")
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets[0].name, "Player")
        XCTAssertEqual(targets[0].stageName, "第3局")
        XCTAssertEqual(targets[0].scoreAverage, 8.2, accuracy: 0.001)
    }

    func testRejectsMalformedEnvelopeAndAPIFailure() {
        XCTAssertThrowsError(try RatingClient.parseTree(Data("not json".utf8)))
        XCTAssertThrowsError(try RatingClient.parseTree(Data(#"{"code":0,"success":false}"#.utf8))) { error in
            XCTAssertEqual(error as? RatingClientError, .apiFailure(0))
        }
        XCTAssertEqual(RatingClient.parseStageSeeds(Data("not json".utf8)).isEmpty, true)
    }

    func testOrderTargetsMatchesAndroidSemantics() {
        let unscored = makeTarget(id: "unscored", nodeID: 1, average: 0, count: 0)
        let high = makeTarget(id: "high", nodeID: 4, average: 9.5, count: 10)
        let low = makeTarget(id: "low", nodeID: 2, average: 2.0, count: 30)
        let middle = makeTarget(id: "middle", nodeID: 3, average: 2.0, count: 5)
        let targets = [unscored, high, low, middle]

        XCTAssertEqual(orderTargets(targets, by: .hot).map(\.bizNo), ["unscored", "high", "low", "middle"])
        XCTAssertEqual(orderTargets(targets, by: .latest).map(\.bizNo), ["high", "middle", "low", "unscored"])
        XCTAssertEqual(orderTargets(targets, by: .highScore).map(\.bizNo), ["high", "low", "middle", "unscored"])
        XCTAssertEqual(orderTargets(targets, by: .lowScore).map(\.bizNo), ["low", "middle", "high", "unscored"])
        XCTAssertEqual(TargetOrder.labels, ["热门", "最新", "高分", "低分"])
    }

    private func makeTarget(id: String, nodeID: Int64, average: Double, count: Int) -> RatingTarget {
        RatingTarget(
            nodeID: nodeID,
            bizType: "lol_item",
            bizNo: id,
            name: id,
            scoreAverage: average,
            scoreCount: count
        )
    }
}
