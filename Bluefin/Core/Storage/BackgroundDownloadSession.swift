//
//  BackgroundDownloadSession.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/22/26.
//

import Foundation

/// Minimal metadata needed to finish writing a `DownloadedTrack` row — round-tripped through
/// `URLSessionTask.taskDescription` (a plain string the OS persists with the task itself) so a
/// download can still be finalized correctly even if iOS fully terminated the app while it was in
/// flight and only relaunched it later to hand off the finished transfer, when nothing about the
/// original `BaseItemDto` survives in memory anymore.
nonisolated struct DownloadTaskPayload: Codable {
    let id: String
    let title: String
    let artistName: String
    let albumName: String
    let albumId: String?
    let durationTicks: Int64

    init(item: BaseItemDto) {
        id = item.Id
        title = item.Name
        artistName = item.AlbumArtist ?? item.Artists?.first ?? ""
        albumName = item.Album ?? ""
        albumId = item.AlbumId
        durationTicks = item.RunTimeTicks ?? 0
    }

    var jsonString: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(from jsonString: String?) -> DownloadTaskPayload? {
        guard let jsonString, let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DownloadTaskPayload.self, from: data)
    }
}

/// Runs downloads on a background `URLSession`, which the OS keeps transferring independently of
/// the app's own process — unlike `URLSession.shared`, whose tasks stop almost immediately once the
/// app leaves the foreground. `UIBackgroundModes: audio` (already declared, for playback) only
/// keeps *audio* alive in the background; it does nothing for arbitrary networking, which is why
/// downloads were stopping as soon as the app was backgrounded or the screen locked.
///
/// Two completion paths exist because the app itself may or may not still be alive when a transfer
/// finishes: if it's still running, `download(remoteURL:payload:)`'s continuation resumes normally;
/// if iOS terminated the app and only relaunched it to deliver the finished transfer (see
/// `AppDelegate.application(_:handleEventsForBackgroundURLSession:completionHandler:)`), there's no
/// continuation waiting, so the delegate callback finalizes the download itself instead, using the
/// task's own `taskDescription` (see `DownloadTaskPayload`) to know what it was for.
final class BackgroundDownloadSession: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = BackgroundDownloadSession()

    private static let sessionIdentifier = "com.bluefin.downloads"

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.allowsCellularAccess = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private let lock = NSLock()
    private var continuations: [Int: CheckedContinuation<(fileURL: URL, response: HTTPURLResponse?), Error>] = [:]

    /// Handed in by `AppDelegate` when iOS relaunches the app specifically to deliver background
    /// session events; called once every pending delegate callback has been replayed.
    var backgroundCompletionHandler: (() -> Void)?

    private override init() {
        super.init()
    }

    /// Ensures the background session exists — called once at launch so a relaunch-to-deliver-events
    /// reconnects to the same session immediately rather than waiting for the first download request.
    func activate() {
        _ = session
    }

    /// Starts (or resumes, if the OS already had one queued) a background transfer, resuming once
    /// the file is safely relocated to a stable temporary location — the location the delegate hands
    /// back is deleted the instant its callback returns, so this hands back a copy the caller owns.
    ///
    /// Wrapped in `withTaskCancellationHandler` deliberately: unlike `URLSession.shared`'s async
    /// convenience methods, a manually-created `URLSessionDownloadTask` doesn't stop on its own when
    /// the enclosing Swift `Task` is cancelled (e.g. via "Cancel Download") — this is what actually
    /// cancels the underlying transfer, surfacing as a thrown error the same way a plain failure does.
    func download(remoteURL: URL, payload: DownloadTaskPayload) async throws -> (fileURL: URL, response: HTTPURLResponse?) {
        let task = session.downloadTask(with: remoteURL)
        task.taskDescription = payload.jsonString

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                continuations[task.taskIdentifier] = continuation
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Must relocate synchronously — the OS deletes `location` as soon as this method returns.
        let stableCopy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let response = downloadTask.response as? HTTPURLResponse

        do {
            try FileManager.default.moveItem(at: location, to: stableCopy)
        } catch {
            complete(taskIdentifier: downloadTask.taskIdentifier, result: .failure(error), payload: nil)
            return
        }

        if let continuation = takeContinuation(for: downloadTask.taskIdentifier) {
            continuation.resume(returning: (stableCopy, response))
            return
        }

        // No continuation waiting means the app process that started this download is gone — finish
        // the job ourselves using only what's recoverable from the task itself.
        guard let payload = DownloadTaskPayload.decode(from: downloadTask.taskDescription) else { return }
        Task {
            await DownloadStore.shared.finalizeColdDownload(payload: payload, tempFileURL: stableCopy, response: response)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        complete(taskIdentifier: task.taskIdentifier, result: .failure(error), payload: nil)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }

    private func takeContinuation(for taskIdentifier: Int) -> CheckedContinuation<(fileURL: URL, response: HTTPURLResponse?), Error>? {
        lock.lock()
        defer { lock.unlock() }
        return continuations.removeValue(forKey: taskIdentifier)
    }

    private func complete(taskIdentifier: Int, result: Result<(fileURL: URL, response: HTTPURLResponse?), Error>, payload: DownloadTaskPayload?) {
        guard let continuation = takeContinuation(for: taskIdentifier) else { return }
        switch result {
        case .success(let value): continuation.resume(returning: value)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }
}
