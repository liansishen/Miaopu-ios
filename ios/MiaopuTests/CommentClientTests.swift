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

    func testRejectsMalformedEnvelopeAndAPIFailure() {
        XCTAssertThrowsError(try CommentClient.parse(Data("not json".utf8)))
        XCTAssertThrowsError(try CommentClient.parse(Data(#"{"code":9,"success":false}"#.utf8))) { error in
            XCTAssertEqual(error as? CommentClientError, .apiFailure(9))
        }
    }
}
