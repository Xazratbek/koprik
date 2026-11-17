import Foundation

/// A problem recognised in a Wine log, with advice the user can act on.
public struct LogFinding: Sendable, Equatable, Identifiable {
    public enum Severity: Int, Sendable, Comparable {
        case info, warning, error

        public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public var id: String
    public var severity: Severity
    public var title: String
    public var advice: String
    /// A winetricks verb that is likely to fix the problem.
    public var suggestedVerb: String?
    /// The first log line that matched.
    public var evidence: String
    public var occurrences: Int
}

/// Numbers that summarise a log.
public struct LogSummary: Sendable, Equatable {
    public var lineCount = 0
    public var errorLines = 0
    public var fixmeLines = 0
    public var findings: [LogFinding] = []
    /// Missing DLLs named in the log, lowercased.
    public var missingLibraries: [String] = []

    public init() {}
}

/// Reads a Wine log and explains the known failure patterns in it.
public enum LogAnalyzer {
    private struct Rule {
        let id: String
        let severity: LogFinding.Severity
        let needles: [String]
        let title: String
        let advice: String
        var verb: String?
    }

    private static let rules: [Rule] = [
        Rule(id: "anticheat", severity: .error,
             needles: ["easyanticheat", "battleye", "beservice", "vgk.sys", "vanguard", "xigncode", "nprotect", "ricochet"],
             title: "Anti-cheat software detected",
             advice: "Kernel-level anti-cheat does not work under Wine. Games that require it cannot be played online here; no setting changes that."),
        Rule(id: "dotnet", severity: .error,
             needles: ["mscoree", "wine mono is not installed", "could not load file or assembly", "clr error", ".net framework"],
             title: ".NET runtime problem",
             advice: "The program needs Microsoft .NET. Install .NET Framework 4.8 or the .NET Desktop Runtime into the bottle.",
             verb: "dotnet48"),
        Rule(id: "vcrun", severity: .error,
             needles: ["msvcp140", "vcruntime140", "msvcr120", "msvcp120", "msvcr110", "msvcr100", "ucrtbase.dll"],
             title: "Visual C++ runtime missing",
             advice: "Install the Microsoft Visual C++ runtime into the bottle.",
             verb: "vcrun2022"),
        Rule(id: "d3dcompiler", severity: .error,
             needles: ["d3dcompiler_47", "d3dcompiler_43", "d3dx9_", "d3dx10_", "d3dx11_", "xinput1_3", "xaudio2_7"],
             title: "DirectX helper library missing",
             advice: "Install the legacy DirectX libraries (d3dcompiler, d3dx9, XAudio) into the bottle.",
             verb: "d3dcompiler_47"),
        Rule(id: "d3d12", severity: .error,
             needles: ["d3d12createdevice", "failed to create d3d12 device", "dx12 is not supported", "directx 12 is not supported", "feature level 12"],
             title: "Direct3D 12 is not available",
             advice: "Direct3D 12 games need Apple's D3DMetal. Import the Game Porting Toolkit in Settings > Graphics, then choose the D3DMetal backend."),
        Rule(id: "d3d11-device", severity: .error,
             needles: ["failed to create d3d11 device", "d3d11createdevice failed", "dxgi_error_unsupported", "no compatible graphics", "directx 11 is required"],
             title: "Direct3D 11 device creation failed",
             advice: "Try another graphics backend for this program: DXMT, then D3DMetal, then DXVK."),
        Rule(id: "avx", severity: .error,
             needles: ["illegal instruction", "avx2 is required", "avx is required", "requires avx", "exception_illegal_instruction", "c000001d"],
             title: "The program needs AVX instructions",
             advice: "Turn on \"Advertise AVX\" for this program. Rosetta can translate AVX and AVX2, but not AVX-512."),
        Rule(id: "vulkan", severity: .warning,
             needles: ["vk_error_", "failed to create vulkan", "vkcreateinstance failed", "vk_khr_swapchain not supported", "moltenvk"],
             title: "Vulkan problem",
             advice: "The program uses Vulkan through MoltenVK, which lacks some features. If the game offers a Direct3D 11 mode, use it with DXMT."),
        Rule(id: "cef", severity: .warning,
             needles: ["steamwebhelper", "cef_", "gpu process isn't usable", "gpu process exited unexpectedly", "libcef"],
             title: "Embedded browser (CEF) trouble",
             advice: "Launchers draw their interface with Chromium. If the window stays black or empty, switch the launcher itself to DXMT or wined3d and restart it."),
        Rule(id: "audio", severity: .warning,
             needles: ["err:mmdevapi", "err:winecoreaudio", "err:dsound", "xaudio2", "failed to initialize audio"],
             title: "Audio problem",
             advice: "If there is no sound, install the XAudio/FAudio libraries with winetricks (xact) or check the macOS output device."),
        Rule(id: "fonts", severity: .info,
             needles: ["err:font", "wine_fontconfig", "missing font", "tahoma", "arial"],
             title: "Fonts missing",
             advice: "Text may look wrong or be missing. Install Microsoft's core fonts into the bottle.",
             verb: "corefonts"),
        Rule(id: "media", severity: .warning,
             needles: ["err:mfplat", "err:quartz", "err:winegstreamer", "media foundation", "mf_e_", "wmvcore"],
             title: "Video playback problem",
             advice: "Cutscenes or videos may not play. A different engine build or the game's own launch option to skip videos can help."),
        Rule(id: "crash", severity: .error,
             needles: ["unhandled exception", "unhandled page fault", "wine: unhandled", "backtrace:", "c0000005"],
             title: "The program crashed",
             advice: "Look at the lines just above the crash for a missing library. Trying another graphics backend or Windows version is the usual next step."),
        Rule(id: "network", severity: .warning,
             needles: ["err:winhttp", "err:wininet", "err:secur32", "err:schannel", "ssl handshake", "certificate"],
             title: "Network or TLS problem",
             advice: "The program could not make a secure connection. Check the Mac's clock and network, then retry."),
        Rule(id: "disk", severity: .error,
             needles: ["no space left", "disk full", "err:ntdll:nt_write_file", "not enough disk space"],
             title: "Disk space problem",
             advice: "Free up space on the Mac, or move the game library to a disk with more room."),
    ]

    public static func analyze(fileAt url: URL, maxBytes: Int = 8 << 20) -> LogSummary {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return LogSummary() }
        defer { try? handle.close() }
        // Long sessions write huge logs; the tail is where the failure is.
        if let size = try? handle.seekToEnd(), size > UInt64(maxBytes) {
            try? handle.seek(toOffset: size - UInt64(maxBytes))
        } else {
            try? handle.seek(toOffset: 0)
        }
        let data = (try? handle.readToEnd()) ?? Data()
        return analyze(String(decoding: data, as: UTF8.self))
    }

    public static func analyze(_ text: String) -> LogSummary {
        var summary = LogSummary()
        var hits: [String: (count: Int, evidence: String)] = [:]
        var missing: [String: Int] = [:]

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            summary.lineCount += 1
            let lowered = line.lowercased()
            if lowered.contains("err:") { summary.errorLines += 1 }
            if lowered.contains("fixme:") { summary.fixmeLines += 1 }

            if let library = missingLibrary(in: lowered) { missing[library, default: 0] += 1 }

            for rule in rules where rule.needles.contains(where: lowered.contains) {
                // A missing-DLL rule only counts when Wine actually failed to load something,
                // or every mention of a DLL name would raise a false alarm.
                if ["vcrun", "d3dcompiler", "dotnet", "fonts"].contains(rule.id),
                   !lowered.contains("err:") && !lowered.contains("not found") && !lowered.contains("failed") { continue }
                if ["cef", "vulkan"].contains(rule.id),
                   !lowered.contains("err") && !lowered.contains("fail") && !lowered.contains("crash") { continue }
                let previous = hits[rule.id]
                hits[rule.id] = ((previous?.count ?? 0) + 1, previous?.evidence ?? String(line.prefix(300)))
            }
        }

        summary.missingLibraries = missing.keys.sorted()
        summary.findings = rules.compactMap { rule in
            guard let hit = hits[rule.id] else { return nil }
            return LogFinding(id: rule.id, severity: rule.severity, title: rule.title, advice: rule.advice,
                              suggestedVerb: rule.verb, evidence: hit.evidence, occurrences: hit.count)
        }
        if !summary.missingLibraries.isEmpty, !summary.findings.contains(where: { ["vcrun", "d3dcompiler", "dotnet"].contains($0.id) }) {
            summary.findings.append(LogFinding(
                id: "missing-dll", severity: .warning, title: "Libraries could not be loaded",
                advice: "Wine could not find: \(summary.missingLibraries.prefix(8).joined(separator: ", ")). Search winetricks for a verb that provides them.",
                suggestedVerb: nil, evidence: summary.missingLibraries.joined(separator: ", "), occurrences: summary.missingLibraries.count
            ))
        }
        summary.findings.sort { $0.severity > $1.severity }
        return summary
    }

    /// Extracts the DLL name from Wine's "Library X.dll ... not found" and
    /// "failed to load X.dll" messages.
    static func missingLibrary(in lowered: String) -> String? {
        guard lowered.contains("not found") || lowered.contains("failed to load") || lowered.contains("could not load") else { return nil }
        guard lowered.contains("err:module") || lowered.contains("err:ole") || lowered.contains("library ") else { return nil }
        for word in lowered.split(whereSeparator: { " \t\"'(),:".contains($0) }) where word.hasSuffix(".dll") {
            let name = word.split(separator: "\\").last.map(String.init) ?? String(word)
            if name.count > 4 { return name }
        }
        return nil
    }
}
