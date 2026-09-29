import XCTest
@testable import Miaopu

final class HupuScheduleParserTests: XCTestCase {
    func testParsesNestedDailyScheduleWithUnknownFields() throws {
        let json = #"{"result":{"dayGameData":[{"day":"2026-06-12","matchData":[{"matchId":"synthetic-01","matchIntroduction":"Cup Final","matchName":"Fallback League","matchStatusDesc":"进行中","matchStartTimeStamp":"1781235845000","againstInfo":{"memberInfos":[{"memberName":"North","memberBaseScore":"2"},{"memberName":"South","memberBaseScore":1}]},"scoreItemKey":{"outBizType":"common","outBizNo":"fixture-01"},"newField":{"ignored":true}}]}]}}"#
        let matches = try HupuScheduleParser.parse(Data(json.utf8), sport: .valorant)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].id, "synthetic-01")
        XCTAssertEqual(matches[0].sport, .valorant)
        XCTAssertEqual(matches[0].league, "Cup Final")
        XCTAssertEqual(matches[0].status, "进行中")
        XCTAssertEqual(matches[0].startTime.timeIntervalSince1970, 1_781_235_845, accuracy: 0.001)
        XCTAssertEqual(matches[0].homeName, "North")
        XCTAssertEqual(matches[0].awayName, "South")
        XCTAssertEqual(matches[0].homeScore, 2)
        XCTAssertEqual(matches[0].awayScore, 1)
        XCTAssertEqual(matches[0].outBizType, "common")
        XCTAssertEqual(matches[0].outBizNo, "fixture-01")
    }

    func testFlattensMultipleDaysAndSkipsMalformedEntries() throws {
        let json = #"{"result":{"dayGameData":[{"matchData":[{"matchId":"broken"},{"matchId":"synthetic-02","matchName":"League B","matchStartTimeStamp":"1781235845000","matchStatusDesc":"未开始","againstInfo":{"memberInfos":[{"memberName":"A"},{"memberName":"B"}]}}]},{"matchData":[{"matchId":"synthetic-03","matchStartTimeStamp":"1781235845000","againstInfo":{"memberInfos":[{"memberName":"C","memberBaseScore":"0"},{"memberName":"D","memberBaseScore":"0"}]}}]}]}}"#
        let matches = try HupuScheduleParser.parse(Data(json.utf8), sport: .basketball)
        XCTAssertEqual(matches.map(\.id), ["synthetic-02", "synthetic-03"])
        XCTAssertEqual(matches[0].league, "League B")
        XCTAssertNil(matches[0].homeScore)
    }

    func testEmptyDayListAndMatchListsAreValid() throws {
        let noDays = #"{"result":{"dayGameData":[]}}"#
        let noMatches = #"{"result":{"dayGameData":[{"matchData":[]}]}}"#
        XCTAssertEqual(try HupuScheduleParser.parse(Data(noDays.utf8), sport: .football), [])
        XCTAssertEqual(try HupuScheduleParser.parse(Data(noMatches.utf8), sport: .football), [])
    }

    func testInvalidEnvelopeThrows() {
        XCTAssertThrowsError(try HupuScheduleParser.parse(Data("[]".utf8), sport: .football))
        XCTAssertThrowsError(try HupuScheduleParser.parse(Data("not json".utf8), sport: .football))
        XCTAssertThrowsError(try HupuScheduleParser.parse(Data(#"{"result":{}}"#.utf8), sport: .football))
    }
}
