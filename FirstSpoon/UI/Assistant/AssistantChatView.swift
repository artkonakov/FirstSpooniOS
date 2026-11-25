import SwiftUI
import UIKit
import FirstSpoonCore

struct AssistantView: View {
    @Environment(AppContainer.self) private var app
    let productId: String?

    var body: some View {
        if AssistantPilot.enabled, let child = app.diary.activeChild {
            let owner = app.tokens.userId ?? "local"
            AssistantChatView(child: child, store: AssistantChatStore(database: app.db, owner: owner, child: child.id),
                              entryProductId: productId)
                .id("\(owner):\(child.id)")
        }
    }
}

private struct AssistantChatView: View {
    @Environment(AppContainer.self) private var app
    @Environment(Navigator.self) private var nav
    let child: Child
    let store: AssistantChatStore
    let entryProductId: String?

    @State private var chat: AssistantConversation?
    @State private var entryProduct: Product?
    @State private var draft = ""
    @State private var history: [AssistantConversation] = []
    @State private var turns: [AssistantTurn] = []
    @State private var initialized = false
    @State private var sending = false
    @State private var requestTask: Task<Void, Never>?
    @State private var requestGeneration: UUID?
    @State private var showHistory = false
    @State private var sourceURL: URL?
    @State private var shareAnswer: SharedAssistantAnswer?
    @State private var showError = false
    @FocusState private var editing: Bool

    private var unfinished: AssistantTurn? {
        guard let last = turns.last, last.reply == nil, !last.stopped else { return nil }
        return last
    }

    private var canSend: Bool {
        initialized && unfinished == nil && draft.utf16.count <= 1000
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if turns.isEmpty {
                        Text(L.s("assistant_privacy")).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted)
                    }
                    ForEach(Array(turns.enumerated()), id: \.element.id) { index, turn in
                        message(turn, first: index == 0)
                    }
                    Color.clear.frame(height: 1).id("assistantBottom")
                }
                .padding(.horizontal, screenPadding)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: turns.count) { _, _ in proxy.scrollTo("assistantBottom", anchor: .bottom) }
            .onChange(of: turns.last?.reply?.answer) { _, _ in proxy.scrollTo("assistantBottom", anchor: .bottom) }
            .onChange(of: chat?.id) { _, _ in proxy.scrollTo("assistantBottom", anchor: .bottom) }
        }
        .bottomAction {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(L.s("assistant_placeholder"), text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .font(AppFont.bodyLarge)
                    .padding(.leading, 12)
                    .padding(.vertical, 10)
                    .focused($editing)
                    .accessibilityIdentifier("assistantComposer")
                    .disabled(sending || unfinished != nil)
                Button {
                    if sending { stopRequest() } else { startTurn() }
                } label: {
                    Image(sending ? "ic_assistant_stop" : "ic_assistant_send")
                        .resizable().frame(width: 23, height: 23)
                        .foregroundStyle(sending || canSend ? AppColors.onPrimary : AppColors.inkMuted)
                        .frame(width: 44, height: 44)
                        .background(sending || canSend ? AppColors.primary : AppColors.surfaceSoft, in: Circle())
                }
                .buttonStyle(AssistantActionStyle())
                .disabled(!sending && !canSend)
                .accessibilityLabel(Text(L.s(sending ? "assistant_stop" : "assistant_send")))
            }
            .padding(6)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppRadius.large))
            .padding(.horizontal, screenPadding)
            .padding(.vertical, 8)
        }
        .appScreen()
        .navigationTitle(L.s("assistant_chat_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L.s("assistant_history")) {
                    editing = false
                    showHistory = true
                    Analytics.track(.assistantHistoryOpened)
                }.disabled(sending)
            }
        }
        .sheet(isPresented: $showHistory) { historySheet }
        .sheet(item: $sourceURL) { url in
            SafariView(url: url, closeStyle: .close)
                .ignoresSafeArea()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $shareAnswer) { value in
            ShareSheet(items: [value.text])
                .onAppear { Analytics.track(.assistantShareOpened) }
        }
        .alert(L.s("assistant_storage_error"), isPresented: $showError) {
            Button(L.s("cancel"), role: .cancel) {}
        }
        .task {
            guard !initialized else { return }
            do {
                history = try store.conversations()
                if let saved = history.first(where: { entryProductId == nil || $0.productId == entryProductId }) {
                    try select(saved)
                } else if let entryProductId, let product = app.catalog.catalog.productsById[entryProductId] {
                    entryProduct = product
                    draft = L.s("assistant_product_question", product.name)
                }
                initialized = true
            } catch { showError = true }
        }
    }

    private func message(_ turn: AssistantTurn, first: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            questionText(turn.question, first: first)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.primarySoft, in: RoundedRectangle(cornerRadius: AppRadius.large))
            .padding(.leading, 32)
            if let reply = turn.reply {
                VStack(alignment: .leading, spacing: 8) {
                    Text(reply.answer).font(AppFont.bodyLarge)
                        .foregroundStyle(reply.kind == "urgent" ? AppColors.alert : AppColors.ink)
                        .textSelection(.enabled)
                    ForEach(reply.sources, id: \.self) { source in
                        if let url = URL(string: source.url), url.scheme == "https", url.host != nil {
                            Button(source.title) {
                                sourceURL = url
                                Analytics.track(.assistantSourceOpened)
                            }
                                .font(AppFont.bodyMedium)
                                .buttonStyle(.plain)
                                .foregroundStyle(AppColors.primary)
                        }
                    }
                    replyActions(turn, reply: reply)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            } else if turn.stopped {
                Text(L.s("assistant_stopped")).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted)
            } else if sending, unfinished?.id == turn.id {
                AssistantThinkingText()
            } else {
                Text(L.s(errorKey(turn.failure))).font(AppFont.bodyMedium).foregroundStyle(AppColors.alert)
                let startsNewRequest = needsNewRequest(turn.failure)
                AppButton(L.s(startsNewRequest ? "assistant_send_again" : "assistant_retry"),
                          kind: .soft, size: .medium, fill: false) { retry(turn, newRequest: startsNewRequest) }
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private func questionText(_ question: String, first: Bool) -> some View {
        if first, let id = chat?.productId, let name = chat?.productName,
           app.catalog.catalog.productsById[id] != nil,
           let target = URL(string: "firstspoon-product://open") {
            var text = AttributedString(question)
            if let range = text.range(of: name, options: .caseInsensitive) {
                let linked = { () -> AttributedString in
                    text[range].link = target
                    return text
                }()
                Text(linked).font(AppFont.bodyLarge).textSelection(.enabled)
                    .environment(\.openURL, OpenURLAction { url in
                        guard url == target else { return .discarded }
                        openProduct(id)
                        return .handled
                    })
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    productLink(id, name: name)
                    Text(question).font(AppFont.bodyLarge).textSelection(.enabled)
                }
            }
        } else {
            Text(question).font(AppFont.bodyLarge).textSelection(.enabled)
        }
    }

    private func replyActions(_ turn: AssistantTurn, reply: AssistantReply) -> some View {
        let sources = reply.sources.filter { URL(string: $0.url)?.scheme == "https" }
        let text = ([reply.answer] + sources.map { "\($0.title): \($0.url)" }).joined(separator: "\n\n")
        return HStack(spacing: 0) {
            replyButton("ic_assistant_copy", "assistant_copy") {
                UIPasteboard.general.string = text
                Analytics.track(.assistantAnswerCopied)
            }
            replyButton(turn.feedback == true ? "ic_assistant_like_fill" : "ic_assistant_like", "assistant_like", selected: turn.feedback == true) {
                vote(turn, positive: true)
            }
            replyButton(turn.feedback == false ? "ic_assistant_dislike_fill" : "ic_assistant_dislike", "assistant_dislike", selected: turn.feedback == false) {
                vote(turn, positive: false)
            }
            replyButton("ic_assistant_share", "assistant_share") { shareAnswer = SharedAssistantAnswer(text: text) }
            if let time = turn.repliedAt {
                Text(Date(timeIntervalSince1970: Double(time) / 1000).formatted(date: .omitted, time: .shortened))
                    .font(AppFont.onest(13, 400))
                    .foregroundStyle(AppColors.inkMuted)
            }
        }
    }

    private func replyButton(_ icon: String, _ label: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(icon).resizable().frame(width: 20, height: 20)
                .foregroundStyle(AppColors.inkMuted)
                .frame(width: 36, height: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(AssistantActionStyle())
        .accessibilityLabel(Text(L.s(label)))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func vote(_ turn: AssistantTurn, positive: Bool) {
        guard currentScope, let chat else { return }
        do {
            if try store.toggleFeedback(turn, positive: positive) {
                turns = try store.messages(chat)
                Analytics.track(.assistantFeedbackTapped(vote: positive ? .like : .dislike))
            }
        } catch { showError = true }
    }

    @ViewBuilder
    private func productLink(_ id: String, name: String) -> some View {
        if app.catalog.catalog.productsById[id] != nil {
            Button(name) { openProduct(id) }
            .font(AppFont.titleSmall)
            .buttonStyle(.bordered)
            .tint(AppColors.primary)
        } else {
            Text(name).font(AppFont.titleSmall).foregroundStyle(AppColors.inkMuted)
        }
    }

    private func openProduct(_ id: String) {
        if case .product(let previous)? = nav.path.dropLast().last, previous == id { nav.back() }
        else { nav.open(.product(id)) }
    }

    private var historySheet: some View {
        NavigationStack {
            List {
                Button(L.s("assistant_new_chat")) {
                    chat = nil; turns = []; draft = ""; entryProduct = nil; showHistory = false
                }
                ForEach(history) { item in
                    Button(item.title) {
                        do {
                            let changed = chat?.id != item.id
                            try select(item)
                            showHistory = false
                            if changed { Analytics.track(.assistantChatSelected) }
                        }
                        catch { showError = true; showHistory = false }
                    }
                    .swipeActions {
                        Button(L.s("delete"), role: .destructive) { delete(item) }
                    }
                }
            }
            .navigationTitle(L.s("assistant_history"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.s("cancel")) { showHistory = false }
                }
            }
        }
    }

    private func select(_ value: AssistantConversation) throws {
        turns = try store.messages(value)
        chat = value
        entryProduct = nil
        draft = ""
    }

    private func delete(_ value: AssistantConversation) {
        do {
            try store.delete(value)
            Analytics.track(.assistantChatDeleted)
            history = try store.conversations()
            if chat?.id == value.id { chat = nil; turns = []; draft = "" }
        } catch { showHistory = false; showError = true }
    }

    private var currentScope: Bool { (app.tokens.userId ?? "local") == store.owner && app.diary.activeChild?.id == child.id }

    private func startTurn() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sending, unfinished == nil, currentScope, !question.isEmpty, question.utf16.count <= 1000 else { return }
        let value = chat ?? AssistantConversation(id: UUID().uuidString, productId: entryProduct?.id,
            productName: entryProduct?.name, title: entryProduct?.name ?? String(question.prefix(80)))
        let id = UUID().uuidString
        let turn = AssistantTurn(id: id, requestId: id, question: question,
                                 context: AssistantContext(app: app, child: child, productId: value.productId),
                                 reply: nil, failure: nil)
        do {
            let createsChat = chat == nil
            try store.append(turn, to: value, create: createsChat)
            if createsChat { Analytics.track(.assistantChatCreated) }
            try select(value)
            Analytics.track(.assistantMessageSent)
            request(turn, in: value)
        } catch { showError = true }
    }

    private func failureReason(_ error: ApiError) -> AnalyticsEvent.AssistantFailure {
        switch error.status {
        case nil: .network
        case 401, 403, 410: .auth
        case 429: .quota
        case let status? where status >= 500: .server
        default: .other
        }
    }

    private func retry(_ turn: AssistantTurn, newRequest: Bool) {
        guard let chat, unfinished?.id == turn.id, !sending, currentScope else { return }
        let retry = AssistantTurn(id: turn.id, requestId: newRequest ? UUID().uuidString : turn.requestId, question: turn.question,
                                  context: turn.context, reply: nil, failure: nil)
        do {
            guard try store.finish(retry, reply: nil, failure: nil) else { return }
            Analytics.track(.assistantRetried)
            request(retry, in: chat)
        } catch { showError = true }
    }

    private func request(_ turn: AssistantTurn, in value: AssistantConversation) {
        sending = true
        editing = false
        let previous = turns.compactMap { item -> [AssistantMessage]? in
            guard let reply = item.reply else { return nil }
            return [AssistantMessage(role: "user", text: item.question), AssistantMessage(role: "assistant", text: reply.answer)]
        }.suffix(3).flatMap { $0 }
        let body = AssistantRequest(requestId: turn.requestId, question: turn.question, history: previous,
                                    locale: turn.context.locale, ageMonths: turn.context.ageMonths, product: turn.context.product)
        let generation = UUID()
        requestGeneration = generation
        requestTask = Task {
            defer {
                if requestGeneration == generation {
                    requestGeneration = nil
                    requestTask = nil
                    sending = false
                }
            }
            guard currentScope else { return }
            let result = await AssistantPilot.reply(api: app.api, request: body, owner: store.owner)
            guard !Task.isCancelled, currentScope else { return }
            do {
                switch result {
                case .success(let reply):
                    if try store.finish(turn, reply: reply, failure: nil) { Analytics.track(.assistantReplyReceived) }
                case .failure(let error):
                    Analytics.track(.assistantRequestFailed(reason: failureReason(error)))
                    let code = error.code ?? (error.isNetwork ? "NETWORK" : "HTTP_\(error.status ?? 0)")
                    try store.finish(turn, reply: nil, failure: code)
                }
                if currentScope {
                    try select(value)
                    history = try store.conversations()
                }
            } catch { showError = true }
        }
    }

    private func stopRequest() {
        guard let chat, let turn = unfinished, requestTask != nil, currentScope else { return }
        do {
            guard try store.stop(turn) else { return }
            requestTask?.cancel()
            requestTask = nil
            requestGeneration = nil
            sending = false
            turns = try store.messages(chat)
            Analytics.track(.assistantRequestStopped)
        } catch { showError = true }
    }

    private func needsNewRequest(_ code: String?) -> Bool {
        code == "ASSISTANT_REQUEST_COMPLETED" || code == "ASSISTANT_REQUEST_UNCERTAIN"
    }

    private func errorKey(_ code: String?) -> String {
        switch code {
        case "NETWORK": return "assistant_network"
        case "AUTHORIZATION_REQUIRED", "ASSISTANT_EMAIL_REQUIRED", "PILOT_ACCESS_REQUIRED", "HTTP_401", "HTTP_403": return "assistant_access"
        case "ASSISTANT_TOKEN_LIMIT", "ASSISTANT_SERVICE_LIMIT", "ASSISTANT_RATE_LIMIT", "ASSISTANT_LIMIT", "HTTP_429": return "assistant_limit"
        case "ASSISTANT_REQUEST_IN_PROGRESS": return "assistant_pending"
        case "ASSISTANT_REQUEST_COMPLETED", "ASSISTANT_REQUEST_UNCERTAIN", nil: return "assistant_interrupted"
        default: return "assistant_error"
        }
    }
}

private struct AssistantThinkingText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let period = 1.8
            let progress = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            let start = -0.5 + 1.5 * progress
            let colors = reduceMotion ? [AppColors.inkMuted, AppColors.inkMuted] : [AppColors.inkMuted, AppColors.primary, AppColors.inkMuted]
            Text(L.s("assistant_pending"))
                .font(AppFont.bodyMedium)
                .foregroundStyle(LinearGradient(colors: colors,
                                                startPoint: UnitPoint(x: start, y: 0.5),
                                                endPoint: UnitPoint(x: start + 0.5, y: 0.5)))
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

private struct SharedAssistantAnswer: Identifiable {
    let id = UUID()
    let text: String
}

private struct AssistantActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.55 : 1)
    }
}
