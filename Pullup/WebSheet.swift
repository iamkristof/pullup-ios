import SwiftUI
import WebKit
import SafariServices

struct WebDestination: Identifiable {
    let id = UUID()
    let path: String
    let title: String
}
struct WebSheet: View {
    let destination: WebDestination
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var loading = true
    @State private var reloadID = UUID()
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                PullupWebView(path: destination.path, loading: $loading, error: $error).id(reloadID)
                if loading { ProgressView().padding().background(.ultraThinMaterial, in: Capsule()).padding() }
                if let error { VStack { ErrorBanner(text: error); Button("Retry") { self.error = nil; reloadID = UUID() } }.padding().background(Palette.background) }
            }.navigationTitle(destination.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { Task { await state.restore() }; dismiss() } } }
        }
    }
}
struct PullupWebView: UIViewRepresentable {
    let path: String
    @Binding var loading: Bool
    @Binding var error: String?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Isolated website storage is discarded with this sheet. Session lives in Keychain.
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.isOpaque = false; view.backgroundColor = .black
        guard let url = URL(string: path, relativeTo: API.origin)?.absoluteURL, url.scheme == "https", url.host == "pullup.at" else { return view }
        Task { @MainActor in
            if let cookie = API.shared.webCookie() { await view.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) }
            view.load(URLRequest(url: url))
        }
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) { context.coordinator.parent = self }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: PullupWebView
        init(_ parent: PullupWebView) { self.parent = parent }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.loading = false
            Task { @MainActor in
                let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                for cookie in cookies where cookie.name == "pullup_session" {
                    do { try API.shared.importCookie(cookie) } catch { parent.error = error.localizedDescription }
                }
            }
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { parent.loading = true }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.loading = false
            if (error as NSError).code != NSURLErrorCancelled { parent.error = "This page could not load. Check your connection and retry." }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { parent.loading = false; parent.error = "This page could not load. Please retry." }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            // Keep the real checkout, challenge and payment redirects intact. Cookies are domain scoped by WebKit.
            if url.scheme == "https" { decisionHandler(.allow) }
            else if ["mailto", "tel"].contains(url.scheme ?? "") { UIApplication.shared.open(url); decisionHandler(.cancel) }
            else { decisionHandler(.cancel) }
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, navigationAction.request.url?.scheme == "https" { webView.load(navigationAction.request) }
            return nil
        }
    }
}
