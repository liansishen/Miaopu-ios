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

    func testParsesImagesRatingsAndDayGroups() throws {
        let json = #"{"result":{"dayGameData":[{"dayTime":"2026-08-06","dateBlock":"8月6日 周四","matchData":[{"matchId":"first","matchStartTimeStamp":"1785999600000","matchStatusDesc":"已结束","againstInfo":{"memberInfos":[{"memberName":"Home","memberLogo":"http://i11.hoopchina.com.cn/team.png"},{"memberName":"Away","memberLogo":"https://i5.hoopchina.com.cn/flag.png"}]},"scoreCountText":"35人评分","scoreItemKey":{"outBizType":"lol_match","outBizNo":"3715"},"scoreItemInfo":{"name":"Player","logo":"https://i5.hoopchina.com.cn/player.png","scoreNum":"9.3","scoreOutBizType":"lol_item","scoreOutBizNo":"8"}}]},{"dayTime":"2026-08-07","dateBlock":"8月7日 周五","matchData":[{"matchId":"second","matchStartTimeStamp":"1786086000000","againstInfo":{"memberInfos":[{"memberName":"C","memberLogo":"https://evil.example/a.png"},{"memberName":"D"}]}}]}]}}"#
        let matches = try HupuScheduleParser.parse(Data(json.utf8), sport: .lol)
        XCTAssertEqual(matches[0].homeLogoURL?.absoluteString, "https://i11.hoopchina.com.cn/team.png")
        XCTAssertEqual(matches[0].awayLogoURL?.absoluteString, "https://i5.hoopchina.com.cn/flag.png")
        XCTAssertEqual(matches[0].scoreCountText, "35人评分")
        XCTAssertEqual(matches[0].featuredRating?.name, "Player")
        XCTAssertEqual(matches[0].featuredRating?.bizId, "8")
        XCTAssertNil(matches[1].homeLogoURL)
        let groups = MatchDay.group(matches)
        XCTAssertEqual(groups.map(\.title), ["8月6日 周四", "8月7日 周五"])
        XCTAssertEqual(groups.map { $0.matches.map(\.id) }, [["first"], ["second"]])
        XCTAssertEqual(MatchDay.group([matches[1]]).map(\.id), ["2026-08-07"])
    }

    func testHomeMergesSportsChronologicallyWithinFiveDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_790_640_000)
        let today = calendar.startOfDay(for: now)
        func match(_ id: String, _ sport: SportCategory, _ day: Int, _ hour: Int) -> Match {
            let time = calendar.date(byAdding: .hour, value: hour, to: calendar.date(byAdding: .day, value: day, to: today)!)!
            let key = DateFormatter()
            key.calendar = calendar
            key.timeZone = calendar.timeZone
            key.dateFormat = "yyyy-MM-dd"
            return Match(id: id, sport: sport, league: "L", startTime: time, homeName: "A", awayName: "B",
                         status: "未开始", dayKey: key.string(from: time), dayTitle: "Day")
        }
        let a = match("same", .lol, 0, 18)
        let b = match("early", .football, 0, 12)
        let c = match("next", .cs2, 2, 9)
        let outside = match("outside", .lol, -3, 8)
        let groups = MatchDay.home([a, outside, c, a, b], now: now, calendar: calendar)
        XCTAssertEqual(groups.flatMap { $0.matches.map(\.id) }, ["early", "same", "next"])
        XCTAssertEqual(groups.count, 2)
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
