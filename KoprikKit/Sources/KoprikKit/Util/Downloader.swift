import Foundation

public struct DownloadProgress: Sendable, Equatable {
    public let receivedBytes: Int64
    /// `nil` when the server did not announce a length.
    public let totalBytes: Int64?

    public var fraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1, Double(receivedBytes) / Double(totalBytes))
    }
}

public enum Downloader {
    /// Downloads `url` to `destination`, replacing any existing file.
    ///
    /// Uses a delegate-based download task because the async `download(from:)`
    /// API does not report byte progress to its delegate.
    public static func download(
        _ url: URL,
        to destination: URL,
        progress: (@Sendable (DownloadProgress) -> Void)? = nil
    ) async throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let delegate = DownloadDelegate(source: url, destination: destination, progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: url)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                delegate.setContinuation(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let source: URL
    private let destination: URL
    private let progress: (@Sendable (DownloadProgress) -> Void)?
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var failure: Error?

    init(source: URL, destination: URL, progress: (@Sendable (DownloadProgress) -> Void)?) {
        self.source = source
        self.destination = destination
        self.progress = progress
    }

    func setContinuation(_ continuation: CheckedContinuation<Void, Error>) {
        lock.withLock { self.continuation = continuation }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        progress?(DownloadProgress(
            receivedBytes: totalBytesWritten,
            totalBytes: totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        ))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The temporary file disappears when this method returns, so it must be moved here.
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            record(KoprikError.downloadFailed(url: source, reason: "HTTP \(http.statusCode)"))
            return
        }
        do {
            let manager = FileManager.default
            if manager.fileExists(atPath: destination.path) {
                try manager.removeItem(at: destination)
            }
            try manager.moveItem(at: location, to: destination)
        } catch {
            record(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (continuation, failure) = lock.withLock {
            let pair = (self.continuation, self.failure)
            self.continuation = nil
            return pair
        }
        session.finishTasksAndInvalidate()

        if let error {
            let wrapped: Error = (error as? URLError)?.code == .cancelled
                ? CancellationError()
                : KoprikError.downloadFailed(url: source, reason: error.localizedDescription)
            continuation?.resume(throwing: wrapped)
        } else if let failure {
            continuation?.resume(throwing: failure)
        } else {
            continuation?.resume()
        }
    }

    private func record(_ error: Error) {
        lock.withLock { if failure == nil { failure = error } }
    }
}
