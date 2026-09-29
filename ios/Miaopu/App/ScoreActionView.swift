import SwiftUI

struct ScoreActionView: View {
    let node: RatingNode

    @EnvironmentObject private var session: HupuSession
    @State private var showingChoices = false
    @State private var showingResult = false
    @State private var resultMessage = ""
    @State private var submitting = false

    var body: some View {
        if let type = node.bizType, let number = node.bizId {
            Button(submitting ? "正在提交评分" : "给这场比赛评分") {
                if session.isAuthenticated {
                    showingChoices = true
                } else {
                    resultMessage = "请先在「我的」中登录虎扑账号。"
                    showingResult = true
                }
            }
            .disabled(submitting)
            .confirmationDialog("选择评分", isPresented: $showingChoices) {
                ForEach([2, 4, 6, 8, 10], id: \.self) { value in
                    Button("\(value) / 10") {
                        Task { await submit(value, type: type, number: number) }
                    }
                }
            }
            .alert("评分", isPresented: $showingResult) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(resultMessage)
            }
        }
    }

    private func submit(_ score: Int, type: String, number: String) async {
        submitting = true
        defer { submitting = false }
        do {
            _ = try await HupuWriteClient().score(
                outBizKey: HupuOutBizKey(outBizType: type, outBizNo: number),
                score: score, cookies: session.cookies
            )
            resultMessage = "评分已提交"
        } catch {
            resultMessage = "评分失败：\(error.localizedDescription)"
        }
        showingResult = true
    }
}
