import Foundation

public enum KoprikError: Error, LocalizedError, Equatable {
    case rosettaMissing
    case engineNotFound(String)
    case engineAlreadyInstalled(String)
    case wineBinaryNotFound(URL)
    case bottleNotFound(String)
    case bottleNameTaken(String)
    case snapshotNotFound(String)
    case checksumMismatch(expected: String, actual: String)
    case downloadFailed(url: URL, reason: String)
    case commandFailed(command: String, status: Int32, output: String)
    case invalidArgument(String)

    public var errorDescription: String? {
        switch self {
        case .rosettaMissing:
            "Rosetta 2 is not installed. Install it with: softwareupdate --install-rosetta --agree-to-license"
        case .engineNotFound(let id):
            "No engine named \"\(id)\" is installed."
        case .engineAlreadyInstalled(let id):
            "Engine \"\(id)\" is already installed."
        case .wineBinaryNotFound(let url):
            "No Wine binary (bin/wine64 or bin/wine) was found under \(url.path)."
        case .bottleNotFound(let name):
            "No bottle named \"\(name)\" exists."
        case .bottleNameTaken(let name):
            "A bottle named \"\(name)\" already exists."
        case .snapshotNotFound(let id):
            "No snapshot \"\(id)\" exists for this bottle."
        case .checksumMismatch(let expected, let actual):
            "Checksum mismatch: expected \(expected), got \(actual). The download is corrupt or was tampered with."
        case .downloadFailed(let url, let reason):
            "Downloading \(url.absoluteString) failed: \(reason)"
        case .commandFailed(let command, let status, let output):
            "\(command) exited with status \(status).\n\(output)"
        case .invalidArgument(let message):
            message
        }
    }
}
