import AppKit
import Foundation

@MainActor
final class GitHubUpdateChecker: ObservableObject {
    struct ReleaseInfo: Sendable {
        let tagName: String
        let htmlURL: String
        let body: String
    }

    /// GitHub 仓库拥有者 / 仓库名
    static let repoOwner = "samwang0041-star"
    static let repoName = "FundBarOpen"

    @Published private(set) var latestRelease: ReleaseInfo?
    @Published private(set) var isUpdateAvailable = false
    @Published private(set) var checkError: String?

    private var hasChecked = false

    /// 当前 App 版本号
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// 启动时检查一次更新
    func checkForUpdatesIfNeeded() async {
        guard !hasChecked else { return }
        hasChecked = true
        await checkForUpdates()
    }

    func checkForUpdates() async {
        let urlString = "https://api.github.com/repos/\(Self.repoOwner)/\(Self.repoName)/releases/latest"
        guard let url = URL(string: urlString) else { return }

        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                checkError = nil
                isUpdateAvailable = false
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String else {
                return
            }

            let body = json["body"] as? String ?? ""
            let release = ReleaseInfo(tagName: tagName, htmlURL: htmlURL, body: body)
            latestRelease = release

            let remoteVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            isUpdateAvailable = compareVersions(remote: remoteVersion, current: currentVersion)
            checkError = nil
        } catch {
            checkError = "检查更新失败：\(error.localizedDescription)"
            isUpdateAvailable = false
        }
    }

    func openReleasePage() {
        guard let release = latestRelease,
              let url = URL(string: release.htmlURL) else { return }
        NSWorkspace.shared.open(url)
    }

    /// 简单版本号比较：remote > current 时返回 true
    private func compareVersions(remote: String, current: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let maxLength = max(remoteParts.count, currentParts.count)

        for i in 0..<maxLength {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if r > c { return true }
            if r < c { return false }
        }
        return false
    }
}
