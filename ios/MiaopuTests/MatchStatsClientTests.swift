import XCTest
@testable import Miaopu

final class MatchStatsClientTests: XCTestCase {
    func testParsesMapsAndTeamTables() throws {
        let json = #"""
        {"success":true,"status":200,"result":{"stats":[
          {"componentCode":"bo_components","defaultAnchor":1,"headingInfo":{"tableDataInfo":[{"requestValue":"0","showName":"全场"},{"requestValue":"1","showName":"第1局"}]}},
          {"componentCode":"single_horizontal_display","bodyInfo":[{"memberPosition":"home","bodyDataInfo":[{},{"showName":"2"}]}]},
          {"componentCode":"list_display_components","belongingCamp":"home","headingInfo":{"tableDataInfo":[
              {"showName":"球员","logo":"https://i11.hoopchina.com.cn/team.png"},{"showName":"得分"},{"showName":"篮板"}]},
            "bodyInfo":[{"bodyDataInfo":[{"showName":"Player A","logo":"https://i11.hoopchina.com.cn/a.png"},{"showName":"30"},{"showName":"3"}]},
                        {"bodyDataInfo":[{"showName":"Player B"},{"showName":"—"},{"showName":"5"}]}]}
        ]}}
        """#
        let stats = MatchStatsClient.parse(Data(json.utf8))
        XCTAssertEqual(stats.maps.map(\.name), ["全场", "第1局"])
        XCTAssertEqual(stats.defaultMapID, "1")
        XCTAssertEqual(stats.teams.count, 1)
        let team = stats.teams[0]
        XCTAssertEqual(team.name, "球员")
        XCTAssertEqual(team.score, "2")
        XCTAssertEqual(team.columns, ["球员", "得分", "篮板"])
        XCTAssertEqual(team.players.count, 2)
        XCTAssertEqual(team.players[0].map(\.text), ["Player A", "30", "3"])
        XCTAssertEqual(team.players[0][0].imageURL?.absoluteString, "https://i11.hoopchina.com.cn/a.png")
        XCTAssertEqual(team.players[1].map(\.text), ["Player B", "—", "5"])
        XCTAssertTrue(stats.hasData)
    }

    func testTreatsMissingBlocksAsEmptyStats() {
        XCTAssertEqual(MatchStatsClient.parse(Data(#"{"success":false,"errorMsg":"no data"}"#.utf8)), .empty)
        XCTAssertEqual(MatchStatsClient.parse(Data("not json".utf8)), .empty)
        XCTAssertFalse(MatchStatsClient.parse(Data(#"{"success":true,"result":{"stats":[]}}"#.utf8)).hasData)
    }
}
