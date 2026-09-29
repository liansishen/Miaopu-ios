import XCTest
@testable import Miaopu

final class RatingClientTests: XCTestCase {
    func testParsesSyntheticRatingTreeIncludingMapNode() throws {
        let json = #"{"code":1,"success":true,"data":{"self":{"node":{"name":"Synthetic Match","scoreAvg":"8.75","scorePersonCount":120,"commentCount":9}},"pageResult":{"data":[{"node":{"name":"Synthetic Team","scoreAvg":9.1,"scorePersonCount":"30","commentCount":2,"bizId":"team-01","bizType":"lol_team"}},{"node":{"name":"Game 1","scoreAvg":7.5,"scorePersonCount":12,"commentCount":1,"bizId":"game-01","bizType":"lol_game"}}]}}}"#
        let detail = try RatingClient.parse(Data(json.utf8))

        XCTAssertEqual(detail.root, RatingNode(id: "root", name: "Synthetic Match", scoreAverage: 8.75, scoreCount: 120, commentCount: 9, bizType: nil, bizId: nil))
        XCTAssertEqual(detail.children.count, 2)
        XCTAssertEqual(detail.children[0], RatingNode(id: "team-01", name: "Synthetic Team", scoreAverage: 9.1, scoreCount: 30, commentCount: 2, bizType: "lol_team", bizId: "team-01"))
        XCTAssertEqual(detail.children[1].id, "game-01")
        XCTAssertEqual(detail.children[1].name, "Game 1")
    }

    func testRejectsMalformedEnvelopeAndAPIFailure() {
        XCTAssertThrowsError(try RatingClient.parse(Data("not json".utf8)))
        XCTAssertThrowsError(try RatingClient.parse(Data(#"{"code":0,"success":false}"#.utf8))) { error in
            XCTAssertEqual(error as? RatingClientError, .apiFailure(0))
        }
    }
}
