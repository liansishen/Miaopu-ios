import XCTest
@testable import Miaopu

final class MatchScoreClientTests: XCTestCase {
    func testParsesEsportsAllMatchScores() throws {
        let json = #"{"code":1,"data":{"matchInfo":{"team1_name":"Home","team1_logo":"http://i5.hoopchina.com.cn/home.png","team2_name":"Away"},"teamScoreInfo":[{"home":false,"playerInfo":[{"playerName":"B","playerScore":9.1}]},{"home":true,"playerInfo":[{"playerName":"A","playerScore":0},{"playerName":"C","playerScore":8.75}]}]}}"#
        let result = try MatchScoreClient.parse(Data(json.utf8), esports: true)
        XCTAssertEqual(result.teams.map(\.name), ["Home", "Away"])
        XCTAssertEqual(result.teams[0].logoURL?.absoluteString, "https://i5.hoopchina.com.cn/home.png")
        XCTAssertEqual(result.teams[0].players.map(\.score), ["—", "8.8"])
        XCTAssertEqual(result.teams[1].players[0].score, "9.1")
        XCTAssertTrue(result.hasScores)
    }

    func testParsesNestedSportsScores() throws {
        let json = #"{"success":true,"result":{"memberBasicInfos":[{"memberName":"A"}],"memberScoreInfos":[[[{"memberName":"P","memberAllAvgScore":"7.5"}]]]}}"#
        let result = try MatchScoreClient.parse(Data(json.utf8), esports: false)
        XCTAssertEqual(result.teams[0].players, [MatchPlayerScore(name: "P", score: "7.5")])
        XCTAssertThrowsError(try MatchScoreClient.parse(Data(#"{"success":false}"#.utf8), esports: false))
    }
}
