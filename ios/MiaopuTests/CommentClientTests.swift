import XCTest
@testable import Miaopu

final class CommentClientTests: XCTestCase {
    func testParsesSyntheticPageAndEmptyPage() throws {
        let json = #"{"code":1,"success":true,"data":{"comments":[{"commentId":"fake-01","commentUserName":"Example User","commentContent":"A fictional comment","lightCount":3,"publishTime":1720000000123,"subCommentCount":2}],"cursor":{"publishTime":1720000000123},"hasMore":true,"commentCount":8}}"#
        let page = try CommentClient.parse(Data(json.utf8))
        XCTAssertEqual(page.comments, [Comment(commentID: "fake-01", userName: "Example User", content: "A fictional comment", lightCount: 3, publishTime: 1_720_000_000_123, subCommentCount: 2)])
        XCTAssertEqual(page.cursor.publishTime, 1_720_000_000_123)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.commentCount, 8)

        let empty = #"{"code":1,"success":true,"data":{"comments":[],"cursor":{"publishTime":0},"hasMore":false,"commentCount":0}}"#
        XCTAssertEqual(try CommentClient.parse(Data(empty.utf8)), CommentPage(comments: [], cursor: CommentCursor(publishTime: 0), hasMore: false, commentCount: 0))
    }

    func testImageURLsAcceptTrustedHTTPSOnly() throws {
        let json = #"{"code":1,"success":true,"data":{"comments":[{"commentId":"fiction-1","commentUserName":"Example","commentContent":"Picture","lightCount":0,"publishTime":1720000000123,"subCommentCount":0,"commentContentImages":[{"commentContentType":"IMAGE","commentContent":"https://i1.hoopchina.com.cn/image.jpg"},{"commentContentType":"IMAGE","commentContent":"https://example.org/other.jpg"}]}],"cursor":{"publishTime":0},"hasMore":false,"commentCount":1}}"#
        let page = try CommentClient.parse(Data(json.utf8))
        XCTAssertEqual(page.comments[0].imageURLs, [URL(string: "https://i1.hoopchina.com.cn/image.jpg")!])
    }

    func testParsesHottestListWithAvatarsAndReplyPreviews() throws {
        let json = #"{"code":1,"success":true,"data":[{"commentId":"hot-1","commentUserName":"Example A","commentContent":"Fictional hot comment","lightCount":208,"publishTime":1720000000000,"subCommentCount":3,"descendantCount":3,"score":2,"commentDate":"08-06","ipLocation":"山东","commentUserHeadImg":"https://i2.hoopchina.com.cn/user.png","commentUserTakeBadge":{"name":"优秀"},"subCommentList":[{"commentId":"reply-1","commentUserName":"Example B","commentContent":"Fictional reply","lightCount":0,"publishTime":1720000000001,"subCommentCount":0}]}]}"#
        let hot = try CommentClient.parseHottest(Data(json.utf8))
        XCTAssertEqual(hot.count, 1)
        XCTAssertEqual(hot[0].avatarURL?.absoluteString, "https://i2.hoopchina.com.cn/user.png")
        XCTAssertEqual(hot[0].score, 2)
        XCTAssertEqual(hot[0].dateText, "08-06")
        XCTAssertEqual(hot[0].location, "山东")
        XCTAssertEqual(hot[0].badgeName, "优秀")
        XCTAssertEqual(hot[0].replyCount, 3)
        XCTAssertEqual(hot[0].previewReplies.map(\.commentID), [])
        XCTAssertThrowsError(try CommentClient.parseHottest(Data(#"{"code":0,"success":false}"#.utf8)))
    }

    func testMergesCommentsByHeatOrder() {
        let first = Comment(commentID: "c1", userName: "A", content: "1", lightCount: 1, publishTime: 1, subCommentCount: 0)
        let second = Comment(commentID: "c2", userName: "B", content: "2", lightCount: 2, publishTime: 2, subCommentCount: 0)
        let third = Comment(commentID: "c3", userName: "C", content: "3", lightCount: 3, publishTime: 3, subCommentCount: 0)
        let merged = mergeComments(byHeat: [first, second], incoming: [second, third], officialHot: ["c3"])
        XCTAssertEqual(merged.map(\.commentID), ["c3", "c1", "c2"])
    }

    func testRejectsMalformedEnvelopeAndAPIFailure() {
        XCTAssertThrowsError(try CommentClient.parse(Data("not json".utf8)))
        XCTAssertThrowsError(try CommentClient.parse(Data(#"{"code":9,"success":false}"#.utf8))) { error in
            XCTAssertEqual(error as? CommentClientError, .apiFailure(9))
        }
    }
}
