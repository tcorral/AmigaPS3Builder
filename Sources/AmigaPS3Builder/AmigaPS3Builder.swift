import AppKit
import Darwin
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Bundled runtime discovery

struct WineRuntime {
    let executable: URL
    let binDirectory: URL
    let prefixURL: URL
    let requiresRosetta: Bool
}

enum EmbeddedRuntime {
    private static let fileManager = FileManager.default
    private static let supportFolderName = "AmigaPS3Builder"

    static var resourcesURL: URL? {
        Bundle.main.resourceURL
    }

    static var isRunningFromAppBundle: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    static func tutorialRoot() -> URL? {
        var seen = Set<String>()
        for candidate in tutorialRootCandidates() {
            let path = candidate.standardizedFileURL.path
            guard seen.insert(path).inserted else { continue }
            if isValidTutorialRoot(candidate) {
                return candidate
            }
        }
        return nil
    }

    static func templateURL() -> URL? {
        guard let root = tutorialRoot() else { return nil }
        return root.appendingPathComponent("CLIKAK500", isDirectory: true)
    }

    private static func isValidTutorialRoot(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.appendingPathComponent("CLIKAK500/USRDIR/EBOOT.BIN").path)
    }

    private static func tutorialRootCandidates() -> [URL] {
        var candidates: [URL] = []
        if let resourcesURL {
            candidates.append(resourcesURL.appendingPathComponent("Tutorial", isDirectory: true))
        }
        candidates.append(contentsOf: ancestorDirectories(startingAt: URL(fileURLWithPath: fileManager.currentDirectoryPath)).map {
            $0.appendingPathComponent("Create Amiga PKG Tutorial", isDirectory: true)
        })
        if let bundleURL = Bundle.main.bundleURL as URL? {
            candidates.append(bundleURL.appendingPathComponent("Contents/Resources/Tutorial", isDirectory: true))
            candidates.append(contentsOf: ancestorDirectories(startingAt: bundleURL).map {
                $0.appendingPathComponent("Create Amiga PKG Tutorial", isDirectory: true)
            })
        }
        let home = fileManager.homeDirectoryForCurrentUser
        candidates.append(home.appendingPathComponent("Downloads/Create Amiga PKG Tutorial", isDirectory: true))
        candidates.append(home.appendingPathComponent("projects/amiga-to-ps3/Create Amiga PKG Tutorial", isDirectory: true))
        candidates.append(URL(fileURLWithPath: "/Applications/AmigaPS3Builder.app/Contents/Resources/Tutorial", isDirectory: true))
        return candidates
    }

    private static func ancestorDirectories(startingAt url: URL) -> [URL] {
        var result: [URL] = []
        var current = url.standardizedFileURL
        for _ in 0..<8 {
            result.append(current)
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return result
    }

    static func trueAncestorURL() -> URL? {
        guard let root = tutorialRoot() else { return nil }
        let folder = root.appendingPathComponent("trueancestor 1.80", isDirectory: true)
        return fileManager.fileExists(atPath: folder.path) ? folder : nil
    }

    static func resignerExecutable() -> URL? {
        guard let folder = trueAncestorURL() else { return nil }
        let resigner = folder.appendingPathComponent("resigner.exe")
        return fileManager.fileExists(atPath: resigner.path) ? resigner : nil
    }

    static func ebootELFSource() -> URL? {
        guard let folder = trueAncestorURL() else { return nil }
        let elf = folder.appendingPathComponent("EBOOT.ELF")
        return fileManager.fileExists(atPath: elf.path) ? elf : nil
    }

    static func packagerExecutable() -> URL? {
        var seen = Set<String>()
        for root in packagerRootCandidates() {
            let path = root.standardizedFileURL.path
            guard seen.insert(path).inserted else { continue }
            if let found = preferredConsolePackager(in: root) {
                return found
            }
        }
        return nil
    }

    private static func packagerRootCandidates() -> [URL] {
        var roots: [URL] = []
        if let resourcesURL {
            roots.append(resourcesURL.appendingPathComponent("Packager", isDirectory: true))
        }
        roots.append(URL(fileURLWithPath: "/Applications/AmigaPS3Builder.app/Contents/Resources/Packager", isDirectory: true))
        if let tutorial = tutorialRoot() {
            roots.append(tutorial.appendingPathComponent("Packager", isDirectory: true))
            roots.append(tutorial)
        }
        return roots
    }

    /// The drag-and-drop `make_pkg.exe` is a .NET/Mono UI tool and often crashes under Wine on macOS.
    /// Automated builds use the native console `psn_package_npdrm.exe` beside its `kit/` data.
    static func preferredConsolePackager(in packagerRoot: URL) -> URL? {
        let npdrm = packagerRoot.appendingPathComponent("kit/psn_package_npdrm.exe")
        if fileManager.fileExists(atPath: npdrm.path) {
            return npdrm
        }
        let makePkg = packagerRoot.appendingPathComponent("make_pkg.exe")
        return fileManager.fileExists(atPath: makePkg.path) ? makePkg : nil
    }

    static func packagerWorkingDirectory(for packagerURL: URL) -> URL {
        let kitDirectory = packagerURL.deletingLastPathComponent()
        if kitDirectory.lastPathComponent.lowercased() == "kit" {
            return kitDirectory
        }
        let nestedKit = packagerURL.deletingLastPathComponent().appendingPathComponent("kit", isDirectory: true)
        if fileManager.fileExists(atPath: nestedKit.appendingPathComponent("psn_package_npdrm.exe").path) {
            return nestedKit
        }
        return packagerURL.deletingLastPathComponent()
    }

    static func wineBundleRoot() -> URL? {
        var roots: [URL] = []
        if let resourcesURL {
            roots.append(resourcesURL.appendingPathComponent("Wine/wine", isDirectory: true))
        }
        roots.append(URL(fileURLWithPath: "/Applications/AmigaPS3Builder.app/Contents/Resources/Wine/wine", isDirectory: true))
        for wineRoot in roots {
            let wineBinary = wineRoot.appendingPathComponent("bin/wine")
            if fileManager.isExecutableFile(atPath: wineBinary.path) {
                return wineRoot
            }
        }
        return nil
    }

    static func winePrefixURL() -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent(supportFolderName, isDirectory: true)
            .appendingPathComponent("wine-prefix", isDirectory: true)
    }

    static func rosettaIsInstalled() -> Bool {
        fileManager.fileExists(atPath: "/usr/libexec/rosetta/runtime")
    }

    private static var resolvedWineByKey: [String: WineRuntime] = [:]
    private static var resolvedWineMisses: Set<String> = []

    static func resolveWine(userOverride: URL?) -> WineRuntime? {
        let key = userOverride?.standardizedFileURL.path ?? "*"
        if let cached = resolvedWineByKey[key] {
            return cached
        }
        if resolvedWineMisses.contains(key) {
            return nil
        }
        guard let resolved = resolveWineUncached(userOverride: userOverride) else {
            resolvedWineMisses.insert(key)
            return nil
        }
        resolvedWineByKey[key] = resolved
        return resolved
    }

    private static func resolveWineUncached(userOverride: URL?) -> WineRuntime? {
        let candidates: [URL] = {
            var list: [URL] = []
            if let userOverride {
                list.append(userOverride)
            }
            if let bundled = wineBundleRoot()?.appendingPathComponent("bin/wine") {
                list.append(bundled)
            }
            if let discovered = discoverSystemWine() {
                list.append(discovered)
            }
            return list
        }()

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
            let binDirectory = candidate.deletingLastPathComponent()
            let requiresRosetta = ProcessInfo.processInfo.machine == "arm64"
                && wineBinaryLooksIntel(candidate)
            return WineRuntime(
                executable: candidate,
                binDirectory: binDirectory,
                prefixURL: winePrefixURL(),
                requiresRosetta: requiresRosetta
            )
        }
        return nil
    }

    static func resolvePackager(userOverride: URL?) -> URL? {
        if let userOverride, fileManager.fileExists(atPath: userOverride.path) {
            return userOverride
        }
        return packagerExecutable()
    }

    static func bundledToolRoot(_ folder: String) -> URL? {
        if let resourcesURL {
            let bundled = resourcesURL.appendingPathComponent("Tools/\(folder)", isDirectory: true)
            if fileManager.fileExists(atPath: bundled.path) {
                return bundled
            }
        }
        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let vendor = cwd.appendingPathComponent("vendor/\(folder)", isDirectory: true)
        return fileManager.fileExists(atPath: vendor.path) ? vendor : nil
    }

    static func bundledToolExecutable(folder: String, name: String) -> URL? {
        guard let root = bundledToolRoot(folder) else { return nil }
        let machine = ProcessInfo.processInfo.machine
        let archFolder: String
        switch machine {
        case "arm64":
            archFolder = "aarch64"
        case "x86_64":
            archFolder = "x86_64"
        default:
            archFolder = machine
        }
        let candidates = [
            root.appendingPathComponent(archFolder).appendingPathComponent(name),
            root.appendingPathComponent(name),
        ]
        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        return nil
    }

    static func at3emuBundleRoot() -> URL? {
        bundledToolRoot("at3emu")
    }

    static func at3emuExecutable() -> URL? {
        bundledToolExecutable(folder: "at3emu", name: "at3emu")
    }

    static func atracdencExecutable() -> URL? {
        bundledToolExecutable(folder: "atracdenc", name: "atracdenc")
    }

    /// at3emu only encodes if Sony PSP SDK files sit beside it (not redistributed).
    static func at3emuCompanionFiles(for executable: URL) -> (at3tool: URL, libatrac: URL?)? {
        let roots = [
            executable.deletingLastPathComponent(),
            executable.deletingLastPathComponent().deletingLastPathComponent(),
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(
                    "Library/Application Support/AmigaPS3Builder/at3tool",
                    isDirectory: true
                )
        ]
        for root in roots {
            let tool = root.appendingPathComponent("linux/at3tool")
            guard fileManager.fileExists(atPath: tool.path) else { continue }
            let lib = root.appendingPathComponent("linux/libatrac.so.1.2.0")
            return (tool, fileManager.fileExists(atPath: lib.path) ? lib : nil)
        }
        return nil
    }

    private static func discoverSystemWine() -> URL? {
        let searchPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            + [
                "/Applications/Wine Stable.app/Contents/Resources/wine/bin",
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/usr/bin"
            ]
        for path in searchPaths {
            let candidate = URL(fileURLWithPath: path).appendingPathComponent("wine")
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Read the Mach-O header. Do not spawn `file` here: SwiftUI evaluates
    /// Wine availability during layout, and `Process.waitUntilExit` re-enters
    /// the run loop and can crash on recent macOS.
    private static func wineBinaryLooksIntel(_ wineURL: URL) -> Bool {
        if let intel = machOContainsIntel(wineURL) {
            return intel
        }
        let wine64 = wineURL.deletingLastPathComponent().appendingPathComponent("wine64")
        if fileManager.isExecutableFile(atPath: wine64.path),
           let intel = machOContainsIntel(wine64) {
            return intel
        }
        return ProcessInfo.processInfo.machine == "arm64"
    }

    private static func machOContainsIntel(_ url: URL) -> Bool? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 256), data.count >= 8 else { return nil }
        if data.starts(with: [0x23, 0x21]) {
            return nil
        }
        let magic = readUInt32(data, at: 0)
        switch magic {
        case 0xFEED_FACF, 0xFEED_FACE:
            let cpu = readUInt32(data, at: 4)
            return cpu == 0x0100_0007 || cpu == 7
        case 0xCFFA_EDFE, 0xCEFA_EDFE:
            let cpu = readUInt32(data, at: 4).byteSwapped
            return cpu == 0x0100_0007 || cpu == 7
        case 0xCAFE_BABE:
            return fatContainsIntel(data, swapped: false)
        case 0xBEBA_FECA:
            return fatContainsIntel(data, swapped: true)
        default:
            return nil
        }
    }

    private static func fatContainsIntel(_ data: Data, swapped: Bool) -> Bool {
        guard data.count >= 8 else { return false }
        var count = readUInt32(data, at: 4)
        if swapped { count = count.byteSwapped }
        var offset = 8
        for _ in 0..<min(Int(count), 8) {
            guard offset + 4 <= data.count else { break }
            var cpu = readUInt32(data, at: offset)
            if swapped { cpu = cpu.byteSwapped }
            if cpu == 0x0100_0007 || cpu == 7 {
                return true
            }
            offset += 20
        }
        return false
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data.subdata(in: offset..<(offset + 4)).withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self)
        }
    }
}

private extension ProcessInfo {
    var machine: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}

// MARK: - Build model

struct BuildOptions {
    var inputs: [URL]
    var title: String
    var titleID: String
    var contentID: String
    var appVersion: String
    var ps3SystemVersion: String
    var templateURL: URL
    var outputURL: URL
    var iconURL: URL?
    var backgroundURL: URL?
    var backgroundVideoURL: URL?
    var musicURL: URL?
    var ebootELFURL: URL?
    var sourceELFIdentifier: String
    var resignerURL: URL?
    var resignEboot: Bool
    var packagerURL: URL?
    var wineURL: URL?
    var debug: Bool
}

struct BuildResult {
    let stagingURL: URL
    let packageURL: URL?
    let messages: [String]
}

enum BuilderError: LocalizedError {
    case invalidTitleID(String)
    case invalidContentID(String)
    case noInput
    case missingTemplate(URL)
    case missingTemplateFile(URL)
    case unsupportedInput(URL)
    case noLHAExtractor
    case lhaHasNoDiskImage(URL)
    case mixedDiskTypes
    case tooManyFloppyDisks(Int)
    case ebootELFRequired
    case ebootIdentifierNotFound(String)
    case resignerRequired
    case resignerMissing(String)
    case resignerOutputMissing(URL)
    case unsupportedMusic(URL)
    case at3EncoderRequired
    case at3EncodeFailed(String)
    case pcmConversionFailed(URL)
    case ffmpegRequired(URL)
    case packagerRequired
    case wineRequired(URL)
    case packagerFailed(String)
    case packageNotProduced(URL)
    case wineRuntimeMissing
    case rosettaRequired
    case incompleteStaging(URL, [String])

    var errorDescription: String? {
        switch self {
        case .invalidTitleID(let value):
            return "Title ID “\(value)” is invalid. It must contain exactly nine uppercase letters or digits."
        case .invalidContentID(let value):
            return "Content ID “\(value)” is invalid. Expected format: PREFIX-TITLEID_00-16CHARACTERS."
        case .noInput:
            return "Add at least one ADF, HDF, or LHA input."
        case .missingTemplate(let url):
            return "The template folder must contain USRDIR/EBOOT.BIN: \(url.path)"
        case .missingTemplateFile(let url):
            return "The template is missing a required file: \(url.path)"
        case .unsupportedInput(let url):
            return "Unsupported Amiga input: \(url.lastPathComponent). Add an ADF, HDF, or LHA file."
        case .noLHAExtractor:
            return "An LHA input needs an extractor. Install lha, unar, or 7-Zip and try again."
        case .lhaHasNoDiskImage(let url):
            return "The LHA archive “\(url.lastPathComponent)” does not contain an ADF or HDF. A generic LHA archive cannot be booted by the supplied UAE configuration."
        case .mixedDiskTypes:
            return "Use either ADF/LHA floppy inputs or one HDF input per package; mixing HDF and floppy images is not supported by this template."
        case .tooManyFloppyDisks(let count):
            return "This emulator template supports at most four floppy slots, but \(count) disk images were selected."
        case .ebootELFRequired:
            return "EBOOT patching needs an EBOOT.ELF source file."
        case .ebootIdentifierNotFound(let identifier):
            return "The EBOOT.ELF source does not contain the expected identifier “\(identifier)”."
        case .resignerRequired:
            return "Automatic EBOOT generation needs TrueAncestor resigner.exe and Wine from the bundled tutorial assets."
        case .resignerMissing(let path):
            return "TrueAncestor resigner.exe was not found at “\(path)”. Reinstall the bundled tutorial assets or disable “Patch EBOOT.ELF…” to prepare without resigning."
        case .resignerOutputMissing(let url):
            return "TrueAncestor completed without producing EBOOT.BIN under \(url.path)."
        case .unsupportedMusic(let url):
            return "Unsupported audio file: \(url.lastPathComponent)"
        case .at3EncoderRequired:
            return "Converting music to SND0.AT3 needs the bundled atracdenc encoder. Rebuild the app with ./scripts/stage-atracdenc.sh, or choose an existing .AT3 file."
        case .at3EncodeFailed(let message):
            return "ATRAC3 encoding failed: \(message)"
        case .pcmConversionFailed(let url):
            return "Could not convert “\(url.lastPathComponent)” to 44.1 kHz stereo WAV. Try another audio file, or choose an existing .AT3 file."
        case .ffmpegRequired(let url):
            return "Converting “\(url.lastPathComponent)” needs ffmpeg. Install it with Homebrew or use a PNG image."
        case .packagerRequired:
            return "The package directory was prepared, but no package builder was configured."
        case .wineRequired(let url):
            return "The selected Windows packager needs Wine on macOS: \(url.path)"
        case .packagerFailed(let message):
            return "The package builder failed: \(message)"
        case .packageNotProduced(let url):
            return "The package builder completed without producing a .pkg under \(url.path)"
        case .wineRuntimeMissing:
            return "Bundled Wine is missing. Rebuild the app with ./scripts/stage-wine-runtime.sh or choose a Wine executable in the UI."
        case .rosettaRequired:
            return "This Mac needs Rosetta 2 to run the bundled Intel Wine runtime. Install it with: softwareupdate --install-rosetta --agree-to-license"
        case .incompleteStaging(let url, let missing):
            return "The staging folder is missing required files (\(missing.joined(separator: ", "))). Build the package again: \(url.path)"
        }
    }
}

// MARK: - PS3 package builder

final class BuildMessageLog {
    private(set) var messages: [String] = []
    private let progress: (@Sendable (String) -> Void)?

    init(progress: (@Sendable (String) -> Void)? = nil) {
        self.progress = progress
    }

    func append(_ line: String) {
        messages.append(line)
        progress?(line)
    }
}

struct PS3PackageBuilder {
    private let fileManager = FileManager.default

    func run(
        options: BuildOptions,
        makePackage: Bool,
        progress: (@Sendable (String) -> Void)? = nil
    ) throws -> BuildResult {
        let log = BuildMessageLog(progress: progress)
        log.append(makePackage ? "Starting package build…" : "Starting staging…")
        let titleID = try normalizedTitleID(options.titleID)
        let contentID = try normalizedContentID(
            options.contentID.isEmpty ? defaultContentID(for: titleID) : options.contentID
        )
        guard !options.inputs.isEmpty else { throw BuilderError.noInput }

        let templateUSRDIR = options.templateURL.appendingPathComponent("USRDIR", isDirectory: true)
        let templateEBOOT = templateUSRDIR.appendingPathComponent("EBOOT.BIN")
        guard fileManager.fileExists(atPath: templateEBOOT.path) else {
            throw BuilderError.missingTemplate(options.templateURL)
        }

        let packageBaseName = options.debug ? "\(titleID)_debug" : titleID
        // The packager needs a directory of assets. Debug keeps that directory
        // beside the package. Otherwise it lives in a temporary folder and is
        // removed once the .pkg has been written.
        let stagingURL: URL
        let removeStagingWhenFinished = makePackage && !options.debug
        if options.debug {
            stagingURL = options.outputURL
                .appendingPathComponent("\(titleID)_debug", isDirectory: true)
        } else if makePackage {
            stagingURL = fileManager.temporaryDirectory
                .appendingPathComponent("amiga-ps3-pkg-\(UUID().uuidString)", isDirectory: true)
        } else {
            stagingURL = options.outputURL
                .appendingPathComponent("\(titleID)_staging", isDirectory: true)
        }
        if fileManager.fileExists(atPath: stagingURL.path) {
            try fileManager.removeItem(at: stagingURL)
        }
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        defer {
            if removeStagingWhenFinished {
                try? fileManager.removeItem(at: stagingURL)
            }
        }

        let rootUSRDIR = stagingURL.appendingPathComponent("USRDIR", isDirectory: true)
        try fileManager.createDirectory(at: rootUSRDIR, withIntermediateDirectories: true)
        log.append("Copying emulator template…")
        try copyTemplate(from: options.templateURL, to: stagingURL, log: log)
        let kickstartName = try kickstartROMName(in: rootUSRDIR)
        if options.resignEboot {
            log.append("Patching EBOOT.ELF and running TrueAncestor through Wine (may take a minute)…")
            try patchAndResignEBOOT(
                options: options,
                titleID: titleID,
                contentID: contentID,
                stagingURL: stagingURL,
                log: log
            )
        }

        let lhaDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("amiga-ps3-builder-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: lhaDirectory) }
        var resolvedInputs: [(source: URL, kind: String)] = []
        for (index, input) in options.inputs.enumerated() {
            let inputWorkDirectory = lhaDirectory.appendingPathComponent("\(index)", isDirectory: true)
            let resolved = try resolveInput(input, workDirectory: inputWorkDirectory, log: log)
            resolvedInputs.append((resolved.url, resolved.kind))
        }
        let kinds = Set(resolvedInputs.map(\.kind))
        guard kinds.count == 1 else { throw BuilderError.mixedDiskTypes }
        let inputKind = resolvedInputs[0].kind
        if inputKind == "hdf" && resolvedInputs.count > 1 {
            throw BuilderError.mixedDiskTypes
        }
        if inputKind == "adf" && resolvedInputs.count > 4 {
            throw BuilderError.tooManyFloppyDisks(resolvedInputs.count)
        }

        var diskNames: [String] = []
        for (index, resolvedInput) in resolvedInputs.enumerated() {
            var diskName = safeFilename(resolvedInput.source.deletingPathExtension().lastPathComponent)
                + "." + resolvedInput.kind
            if diskName.lowercased() == "savedisk.adf" || diskNames.contains(diskName) {
                diskName = "game-\(index + 1)-\(diskName)"
            }
            let diskURL = rootUSRDIR.appendingPathComponent(diskName)
            try fileManager.copyItem(at: resolvedInput.source, to: diskURL)
            diskNames.append(diskName)
            log.append("Input: \(options.inputs[index].lastPathComponent) → \(diskName) (\(resolvedInput.kind.uppercased()))")
        }

        let saveDiskURL = rootUSRDIR.appendingPathComponent("savedisk.adf")
        if inputKind == "adf", diskNames.count == 1,
           fileManager.fileExists(atPath: saveDiskURL.path) {
            let stem = (diskNames[0] as NSString).deletingPathExtension
            let saveAlias = "\(stem)_save.adf"
            let aliasURL = rootUSRDIR.appendingPathComponent(saveAlias)
            if !fileManager.fileExists(atPath: aliasURL.path) {
                try fileManager.copyItem(at: saveDiskURL, to: aliasURL)
                log.append("Created \(saveAlias) for the PS3 UAE save-disk lookup.")
            }
        }
        let configURL = rootUSRDIR.appendingPathComponent("UAE.CFG")
        let templateConfigURL = options.templateURL.appendingPathComponent("USRDIR/UAE.CFG")
        try writeUAEConfig(
            templateURL: templateConfigURL,
            destination: configURL,
            titleID: titleID,
            inputKind: inputKind,
            diskNames: diskNames,
            kickstartName: kickstartName,
            hasSaveDisk: inputKind == "adf" && diskNames.count == 1 &&
                fileManager.fileExists(atPath: saveDiskURL.path),
            log: log
        )

        try writeSFO(
            to: stagingURL.appendingPathComponent("PARAM.SFO"),
            title: options.title,
            titleID: titleID,
            appVersion: options.appVersion,
            ps3SystemVersion: options.ps3SystemVersion
        )
        log.append("PARAM.SFO generated for \(options.title) (\(titleID)).")

        if let iconURL = options.iconURL {
            try materializeImage(iconURL, destination: stagingURL.appendingPathComponent("ICON0.PNG"))
            log.append("ICON0.PNG generated from \(iconURL.lastPathComponent).")
        }
        if let backgroundURL = options.backgroundURL {
            try materializeImage(backgroundURL, destination: stagingURL.appendingPathComponent("PIC1.PNG"))
            log.append("PIC1.PNG generated from \(backgroundURL.lastPathComponent).")
        } else if let videoURL = options.backgroundVideoURL {
            try materializeVideoFrame(videoURL, destination: stagingURL.appendingPathComponent("PIC1.PNG"))
            log.append("PIC1.PNG generated from the first frame of \(videoURL.lastPathComponent).")
            log.append("PS3 XMB background video note: this pipeline stores a static PIC1.PNG frame; the supplied package format does not provide a standard video background slot.")
        }
        let iconDestination = stagingURL.appendingPathComponent("ICON0.PNG")
        guard fileManager.fileExists(atPath: iconDestination.path) else {
            throw BuilderError.missingTemplateFile(iconDestination)
        }
        if let musicURL = options.musicURL {
            try materializeMusic(
                musicURL,
                destination: stagingURL.appendingPathComponent("SND0.AT3"),
                log: log
            )
        }

        try writePackageConfiguration(
            to: stagingURL.appendingPathComponent("package.conf"),
            contentID: contentID,
            titleID: titleID,
            version: options.appVersion
        )
        log.append("package.conf generated with Content ID \(contentID) (install path derived from PARAM.SFO TITLE_ID).")
        if removeStagingWhenFinished {
            log.append("Prepared package files.")
        } else {
            log.append("Prepared package directory: \(stagingURL.path)")
        }
        if !options.resignEboot {
            log.append("NPDRM note: EBOOT patch/resign is disabled; the template EBOOT.BIN was retained byte-for-byte.")
        }

        var packageURL: URL?
        if makePackage {
            guard let packagerURL = options.packagerURL else {
                throw BuilderError.packagerRequired
            }
            try validateStagingForPackage(at: stagingURL)
            log.append("Running Windows package builder through Wine…")
            packageURL = try runPackager(
                packagerURL: packagerURL,
                wineURL: options.wineURL,
                stagingURL: stagingURL,
                outputURL: options.outputURL,
                packageBaseName: packageBaseName,
                log: log
            )
        }

        if removeStagingWhenFinished, fileManager.fileExists(atPath: stagingURL.path) {
            try fileManager.removeItem(at: stagingURL)
            log.append("Removed temporary package folder.")
        }

        let manifestURL = options.outputURL.appendingPathComponent("\(titleID)-build.txt")
        try writeManifest(
            to: manifestURL,
            title: options.title,
            titleID: titleID,
            contentID: contentID,
            stagingDirectory: removeStagingWhenFinished ? "not kept" : stagingURL.path,
            packageURL: packageURL,
            messages: log.messages
        )

        return BuildResult(stagingURL: stagingURL, packageURL: packageURL, messages: log.messages)
    }

    private func normalizedTitleID(_ value: String) throws -> String {
        let upper = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let allowed = upper.unicodeScalars.allSatisfy {
            ($0.value >= 48 && $0.value <= 57) ||
            ($0.value >= 65 && $0.value <= 90)
        }
        guard upper.count == 9, allowed else {
            throw BuilderError.invalidTitleID(value)
        }
        return upper
    }

    private func normalizedContentID(_ value: String) throws -> String {
        let upper = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let pattern = "^[A-Z0-9]{6}-[A-Z0-9]{9}_00-[A-Z0-9]{16}$"
        guard upper.range(of: pattern, options: .regularExpression) != nil else {
            throw BuilderError.invalidContentID(value)
        }
        return upper
    }

    private func defaultContentID(for titleID: String) -> String {
        "JP9000-\(titleID)_00-0000000000000000"
    }

    private func patchAndResignEBOOT(
        options: BuildOptions,
        titleID: String,
        contentID: String,
        stagingURL: URL,
        log: BuildMessageLog
    ) throws {
        guard let ebootELFURL = options.ebootELFURL else {
            throw BuilderError.ebootELFRequired
        }
        guard let resignerURL = options.resignerURL else {
            throw BuilderError.resignerRequired
        }
        guard fileManager.fileExists(atPath: resignerURL.path) else {
            throw BuilderError.resignerMissing(resignerURL.path)
        }
        guard let wineRuntime = EmbeddedRuntime.resolveWine(userOverride: options.wineURL) else {
            throw BuilderError.wineRuntimeMissing
        }
        try validateRosetta(for: wineRuntime)

        let identifier = Array(options.sourceELFIdentifier.utf8)
        let replacement = Array(titleID.utf8)
        guard identifier.count == replacement.count, !identifier.isEmpty else {
            throw BuilderError.ebootIdentifierNotFound(options.sourceELFIdentifier)
        }
        let sourceData = try Data(contentsOf: ebootELFURL)
        var patchedBytes = Array(sourceData)
        var matches = 0
        if patchedBytes.count >= identifier.count {
            for index in 0...(patchedBytes.count - identifier.count) {
                if Array(patchedBytes[index..<(index + identifier.count)]) == identifier {
                    patchedBytes.replaceSubrange(index..<(index + replacement.count), with: replacement)
                    matches += 1
                }
            }
        }
        guard matches > 0 else {
            throw BuilderError.ebootIdentifierNotFound(options.sourceELFIdentifier)
        }

        let auditURL = options.outputURL.appendingPathComponent("\(titleID)-EBOOT.ELF")
        try Data(patchedBytes).write(to: auditURL, options: .atomic)
        log.append("Patched \(matches) EBOOT.ELF occurrence(s): \(options.sourceELFIdentifier) → \(titleID).")

        let resignWorkspace = fileManager.temporaryDirectory
            .appendingPathComponent("amiga-ps3-resign-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: resignWorkspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: resignWorkspace) }

        let resignerDirectory = resignerURL.deletingLastPathComponent()
        let toolFiles = try fileManager.contentsOfDirectory(
            at: resignerDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        for toolFile in toolFiles {
            let destination = resignWorkspace.appendingPathComponent(toolFile.lastPathComponent)
            try fileManager.copyItem(at: toolFile, to: destination)
        }
        let workingELF = resignWorkspace.appendingPathComponent("EBOOT.ELF")
        try Data(patchedBytes).write(to: workingELF, options: .atomic)
        let workingResigner = resignWorkspace.appendingPathComponent(resignerURL.lastPathComponent)
        guard fileManager.fileExists(atPath: workingResigner.path) else {
            throw BuilderError.resignerRequired
        }

        // TrueAncestor option 3 is the interactive “4.21 EBOOT resigner”
        // flow shown in the supplied tutorial.
        let scriptedInput = "3\n\(contentID)\n\nx\n"
        let result = try runWineProcess(
            runtime: wineRuntime,
            arguments: [workingResigner.path],
            currentDirectory: resignWorkspace,
            input: scriptedInput
        )
        if result.status != 0 {
            throw BuilderError.packagerFailed(result.output)
        }

        let generatedEBOOT = resignWorkspace.appendingPathComponent("EBOOT.BIN")
        guard fileManager.fileExists(atPath: generatedEBOOT.path) else {
            throw BuilderError.resignerOutputMissing(resignWorkspace)
        }
        try replaceItem(
            generatedEBOOT,
            destination: stagingURL.appendingPathComponent("USRDIR/EBOOT.BIN")
        )
        log.append("TrueAncestor generated and installed a new EBOOT.BIN for \(contentID).")
        if !result.output.isEmpty {
            log.append("TrueAncestor: \(result.output)")
        }
    }

    private func copyTemplate(from source: URL, to destination: URL, log: BuildMessageLog) throws {
        guard fileManager.fileExists(atPath: source.appendingPathComponent("USRDIR/EBOOT.BIN").path) else {
            throw BuilderError.missingTemplate(source)
        }
        let rootFiles = ["ICON0.PNG", "PIC1.PNG", "SND0.AT3", "PS3LOGO.DAT"]
        for name in rootFiles {
            let sourceURL = source.appendingPathComponent(name)
            let destinationURL = destination.appendingPathComponent(name)
            if fileManager.fileExists(atPath: sourceURL.path) {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }
        }

        let sourceUSRDIR = source.appendingPathComponent("USRDIR", isDirectory: true)
        let destinationUSRDIR = destination.appendingPathComponent("USRDIR", isDirectory: true)
        let items = try fileManager.contentsOfDirectory(
            at: sourceUSRDIR,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for item in items {
            let name = item.lastPathComponent
            let lower = name.lowercased()
            if lower == "uae.cfg" || lower == "savedisk.adf" ||
                lower.hasSuffix(".adf") || lower.hasSuffix(".hdf") || lower.hasSuffix(".lha") {
                continue
            }
            let destinationItem = destinationUSRDIR.appendingPathComponent(name)
            if fileManager.fileExists(atPath: destinationItem.path) {
                try fileManager.removeItem(at: destinationItem)
            }
            try fileManager.copyItem(at: item, to: destinationItem)
        }

        // The save disk is part of the emulator template, not the selected game.
        let saveDisk = sourceUSRDIR.appendingPathComponent("savedisk.adf")
        if fileManager.fileExists(atPath: saveDisk.path) {
            try fileManager.copyItem(
                at: saveDisk,
                to: destinationUSRDIR.appendingPathComponent("savedisk.adf")
            )
            log.append("Preserved template save disk: savedisk.adf.")
        }
        log.append("Copied emulator template and ROM files.")
    }

    private func resolveInput(
        _ source: URL,
        workDirectory: URL,
        log: BuildMessageLog
    ) throws -> (url: URL, kind: String) {
        let extensionName = source.pathExtension.lowercased()
        if extensionName == "adf" || extensionName == "hdf" {
            return (source, extensionName)
        }
        guard extensionName == "lha" else {
            throw BuilderError.unsupportedInput(source)
        }

        try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        guard let extractor = findExecutable(named: ["lha", "unar", "7z", "bsdtar"]) else {
            throw BuilderError.noLHAExtractor
        }
        let extractorName = URL(fileURLWithPath: extractor).lastPathComponent.lowercased()
        let arguments: [String]
        if extractorName == "lha" {
            arguments = ["x", source.path, workDirectory.path]
        } else if extractorName == "unar" {
            arguments = ["-f", "-o", workDirectory.path, source.path]
        } else if extractorName == "7z" {
            arguments = ["x", "-y", "-o\(workDirectory.path)", source.path]
        } else {
            arguments = ["-xf", source.path, "-C", workDirectory.path]
        }
        let result = try runProcess(executable: extractor, arguments: arguments, currentDirectory: nil)
        guard result.status == 0 else {
            throw BuilderError.packagerFailed(result.output.isEmpty ? "LHA extraction failed." : result.output)
        }
        let enumerator = fileManager.enumerator(
            at: workDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        let disks = enumerator?.compactMap { item -> URL? in
            guard let url = item as? URL else { return nil }
            let ext = url.pathExtension.lowercased()
            return (ext == "adf" || ext == "hdf") ? url : nil
        } ?? []
        guard let disk = disks.sorted(by: { $0.path < $1.path }).first else {
            throw BuilderError.lhaHasNoDiskImage(source)
        }
        let kind = disk.pathExtension.lowercased()
        log.append("Extracted \(source.lastPathComponent) and selected \(disk.lastPathComponent).")
        return (disk, kind)
    }

    private func writeUAEConfig(
        templateURL: URL,
        destination: URL,
        titleID: String,
        inputKind: String,
        diskNames: [String],
        kickstartName: String,
        hasSaveDisk: Bool,
        log: BuildMessageLog
    ) throws {
        let base: String
        if fileManager.fileExists(atPath: templateURL.path) {
            base = try String(contentsOf: templateURL, encoding: .utf8)
        } else {
            base = """
            kickstart_rom_file=/dev_hdd0/game/\(titleID)/USRDIR/kick31.rom
            chipmem_size=4
            fastmem_size=8
            use_gui=no
            nr_floppies=2
            cpu_type=68020
            cpu_speed=max
            cpu_cycle_exact=false
            cpu_compatible=true
            blitter_cycle_exact=true
            chipset=ECS_AGNUS
            ntsc=false
            gfx_width=720
            gfx_height=576
            gfx_linemode=double
            gfx_framerate=1
            sound_output=normal
            sound_channels=stereo
            sound_bits=16
            sound_frequency=44100
            show_leds=false
            hardfile=
            floppy_speed=800
            gfx_center_vertical=smart
            gfx_center_horizontal=smart
            gfx_color_mode=32
            """
        }

        let basePath = "/dev_hdd0/game/\(titleID)/USRDIR/"
        var values: [String: String] = [
            "kickstart_rom_file": basePath + kickstartName,
            "hardfile": "",
            "nr_floppies": inputKind == "adf"
                ? String(diskNames.count + (hasSaveDisk ? 1 : 0))
                : "0"
        ]
        for index in 0..<4 {
            values["floppy\(index)"] = ""
        }
        if inputKind == "adf" {
            for (index, diskName) in diskNames.enumerated() {
                values["floppy\(index)"] = basePath + diskName
            }
            if hasSaveDisk {
                values["floppy\(diskNames.count)"] = basePath + "savedisk.adf"
            }
        } else {
            values["hardfile"] = basePath + diskNames[0]
        }

        var seen = Set<String>()
        let lines = base.components(separatedBy: .newlines).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let separator = trimmed.firstIndex(of: "=") else { return line }
            let key = String(trimmed[..<separator])
            guard let value = values[key] else { return line }
            seen.insert(key)
            return "\(key)=\(value)"
        }
        var output = lines.joined(separator: "\n")
        for (key, value) in values where !seen.contains(key) {
            output += "\n\(key)=\(value)"
        }
        try output.write(to: destination, atomically: true, encoding: .utf8)
        log.append("UAE.CFG points to \(diskNames.count) selected \(inputKind.uppercased()) image(s).")
    }

    private func kickstartROMName(in usrdir: URL) throws -> String {
        for preferred in ["kick31.rom", "kick13.rom", "kick12.rom"] {
            if fileManager.fileExists(atPath: usrdir.appendingPathComponent(preferred).path) {
                return preferred
            }
        }
        let items = try fileManager.contentsOfDirectory(
            at: usrdir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        if let kickstart = items
            .filter({ $0.pathExtension.lowercased() == "rom" })
            .filter({ $0.deletingPathExtension().lastPathComponent.lowercased().hasPrefix("kick") })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            .first {
            return kickstart.lastPathComponent
        }
        throw BuilderError.missingTemplateFile(usrdir.appendingPathComponent("kick31.rom"))
    }

    private func writeSFO(
        to url: URL,
        title: String,
        titleID: String,
        appVersion: String,
        ps3SystemVersion: String
    ) throws {
        struct Field {
            let key: String
            let type: UInt16
            let data: Data
            let maxLength: UInt32
        }

        func stringField(_ key: String, _ value: String, maxLength: Int? = nil) -> Field {
            let raw = Data(value.utf8) + Data([0])
            let requested = maxLength ?? max(4, raw.count)
            let paddedLength = ((requested + 3) / 4) * 4
            return Field(
                key: key,
                type: 0x0204,
                data: raw,
                maxLength: UInt32(paddedLength)
            )
        }

        func integerField(_ key: String, _ value: UInt32) -> Field {
            var raw = Data()
            raw.appendLittleEndian(value)
            return Field(key: key, type: 0x0404, data: raw, maxLength: 4)
        }

        let license = "This application was created with the official non-official SDK called psl1ght, for more information visit http://www.psl1ght.com/ . This is in no way associated with Sony Computer Entertainment Inc., please do not contact them for help, they will not be able to provide it."
        let fields = [
            stringField("APP_VER", appVersion, maxLength: 8),
            integerField("ATTRIBUTE", 0),
            integerField("BOOTABLE", 1),
            stringField("CATEGORY", "HG", maxLength: 4),
            stringField("LICENSE", license, maxLength: 512),
            integerField("PARENTAL_LEVEL", 0),
            stringField("PS3_SYSTEM_VER", ps3SystemVersion, maxLength: 8),
            integerField("RESOLUTION", 63),
            integerField("SOUND_FORMAT", 279),
            stringField("TITLE", String(title.prefix(127)), maxLength: 128),
            stringField("TITLE_ID", titleID, maxLength: 16),
            stringField("VERSION", appVersion, maxLength: 8)
        ]

        var keys = Data()
        var keyOffsets: [UInt16] = []
        for field in fields {
            keyOffsets.append(UInt16(keys.count))
            keys.append(contentsOf: field.key.utf8)
            keys.append(0)
        }
        let keyOffset = UInt32(20 + fields.count * 16)
        let dataOffset = align4(keyOffset + UInt32(keys.count))
        var output = Data()
        output.append(contentsOf: [0x00, 0x50, 0x53, 0x46])
        output.appendLittleEndian(UInt32(0x101))
        output.appendLittleEndian(keyOffset)
        output.appendLittleEndian(dataOffset)
        output.appendLittleEndian(UInt32(fields.count))

        var dataIndex: UInt32 = 0
        for (index, field) in fields.enumerated() {
            output.appendLittleEndian(keyOffsets[index])
            output.appendLittleEndian(field.type)
            output.appendLittleEndian(UInt32(field.data.count))
            output.appendLittleEndian(field.maxLength)
            output.appendLittleEndian(dataIndex)
            dataIndex += field.maxLength
        }
        output.append(keys)
        while output.count < Int(dataOffset) {
            output.append(0)
        }
        for field in fields {
            output.append(field.data)
            let padding = Int(field.maxLength) - field.data.count
            if padding > 0 {
                output.append(contentsOf: Array(repeating: UInt8(0), count: padding))
            }
        }
        try output.write(to: url, options: .atomic)
    }

    private func writePackageConfiguration(
        to url: URL,
        contentID: String,
        titleID: String,
        version: String
    ) throws {
        // psn_package_npdrm rejects explicit installdirectory under Wine (InstallDirectory
        // validation fails even when the path includes the Title ID). Omit it; PARAM.SFO
        // supplies TITLE_ID and the tool picks the install path automatically.
        let lines = [
            "contentid=\(contentID)",
            "drmtype=Free",
            "klicensee=00000000000000000000000000000000",
            "contenttype=GameExec",
            "packageversion=\(version)",
            "titleid=\(titleID)",
        ]
        let configuration = lines.joined(separator: "\n") + "\n"
        try configuration.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    private func writeManifest(
        to url: URL,
        title: String,
        titleID: String,
        contentID: String,
        stagingDirectory: String,
        packageURL: URL?,
        messages: [String]
    ) throws {
        var text = """
        Amiga → PS3 build
        Title: \(title)
        Title ID: \(titleID)
        Content ID: \(contentID)
        Staging directory: \(stagingDirectory)
        Package: \(packageURL?.path ?? "not built")

        """
        text += messages.map { "• \($0)" }.joined(separator: "\n")
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func materializeImage(_ source: URL, destination: URL) throws {
        let ext = source.pathExtension.lowercased()
        if ext == "png" {
            try replaceItem(source, destination: destination)
            return
        }
        try convertWithFFmpeg(source: source, destination: destination)
    }

    private func materializeVideoFrame(_ source: URL, destination: URL) throws {
        try convertWithFFmpeg(source: source, destination: destination)
    }

    private func materializeMusic(
        _ source: URL,
        destination: URL,
        log: BuildMessageLog
    ) throws {
        let ext = source.pathExtension.lowercased()
        if ext == "at3" {
            try replaceItem(source, destination: destination)
            log.append("SND0.AT3 copied from \(source.lastPathComponent).")
            return
        }
        try convertToAT3(source: source, destination: destination)
        log.append("SND0.AT3 encoded from \(source.lastPathComponent).")
    }

    private func convertToAT3(source: URL, destination: URL) throws {
        let tempWAV = fileManager.temporaryDirectory
            .appendingPathComponent("amiga-ps3-pcm-\(UUID().uuidString).wav")
        defer { try? fileManager.removeItem(at: tempWAV) }
        try convertToPCMWAV(source: source, destination: tempWAV)

        var lastFailure = ""
        if let atracdenc = resolveToolExecutable(
            preferred: EmbeddedRuntime.atracdencExecutable(),
            names: ["atracdenc", "atracdenc.exe"]
        ) {
            if try encodeWithAtracdenc(
                executable: atracdenc,
                wav: tempWAV,
                destination: destination,
                lastFailure: &lastFailure
            ) {
                return
            }
        }

        if let at3emu = resolveToolExecutable(
            preferred: EmbeddedRuntime.at3emuExecutable(),
            names: ["at3emu"]
        ), let companions = EmbeddedRuntime.at3emuCompanionFiles(for: URL(fileURLWithPath: at3emu)) {
            var arguments = ["--at3tool", companions.at3tool.path]
            if let libatrac = companions.libatrac {
                arguments += ["--libatrac", libatrac.path]
            }
            arguments += ["-e", "-br", "132", tempWAV.path, destination.path]
            let workingDirectory = companions.at3tool
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let result = try runProcess(
                executable: at3emu,
                arguments: arguments,
                currentDirectory: workingDirectory
            )
            if result.status == 0, fileManager.fileExists(atPath: destination.path) {
                return
            }
            lastFailure = result.output
        }

        if lastFailure.isEmpty {
            throw BuilderError.at3EncoderRequired
        }
        throw BuilderError.at3EncodeFailed(lastFailure)
    }

    private func encodeWithAtracdenc(
        executable: String,
        wav: URL,
        destination: URL,
        lastFailure: inout String
    ) throws -> Bool {
        let attempts: [[String]] = [
            ["-e", "atrac3", "--container", "riff", "--sony-delay-align", "-i", wav.path, "-o", destination.path],
            ["-e", "atrac3", "--container", "riff", "-i", wav.path, "-o", destination.path],
            ["-e", "atrac3", "-i", wav.path, "-o", destination.path]
        ]
        for arguments in attempts {
            let result = try runProcess(
                executable: executable,
                arguments: arguments,
                currentDirectory: nil
            )
            if result.status == 0, fileManager.fileExists(atPath: destination.path) {
                return true
            }
            lastFailure = result.output
            if !result.output.contains("unrecognized") && !result.output.contains("unexpected argument") {
                break
            }
        }
        return false
    }

    private func convertToPCMWAV(source: URL, destination: URL) throws {
        let afconvert = "/usr/bin/afconvert"
        if fileManager.isExecutableFile(atPath: afconvert) {
            let result = try runProcess(
                executable: afconvert,
                arguments: [
                    "-f", "WAVE",
                    "-d", "LEI16@44100",
                    "-c", "2",
                    source.path,
                    destination.path
                ],
                currentDirectory: nil
            )
            if result.status == 0, fileManager.fileExists(atPath: destination.path) {
                return
            }
        }

        guard let ffmpeg = findExecutable(named: ["ffmpeg"]) else {
            throw BuilderError.pcmConversionFailed(source)
        }
        let result = try runProcess(
            executable: ffmpeg,
            arguments: [
                "-y", "-i", source.path,
                "-ac", "2", "-ar", "44100", "-sample_fmt", "s16",
                destination.path
            ],
            currentDirectory: nil
        )
        guard result.status == 0, fileManager.fileExists(atPath: destination.path) else {
            throw BuilderError.pcmConversionFailed(source)
        }
    }

    private func convertWithFFmpeg(source: URL, destination: URL) throws {
        guard let ffmpeg = findExecutable(named: ["ffmpeg"]) else {
            throw BuilderError.ffmpegRequired(source)
        }
        let result = try runProcess(
            executable: ffmpeg,
            arguments: ["-y", "-i", source.path, "-frames:v", "1", destination.path],
            currentDirectory: nil
        )
        guard result.status == 0 else {
            throw BuilderError.packagerFailed(result.output)
        }
    }

    private func validateStagingForPackage(at stagingURL: URL) throws {
        let required = [
            "PARAM.SFO",
            "package.conf",
            "ICON0.PNG",
            "USRDIR/EBOOT.BIN"
        ]
        let missing = required.filter { name in
            !fileManager.fileExists(atPath: stagingURL.appendingPathComponent(name).path)
        }
        guard missing.isEmpty else {
            throw BuilderError.incompleteStaging(stagingURL, missing)
        }
    }

    private func sanitizedProcessOutput(_ text: String) -> String {
        let filtered = text.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            let value = String(line)
            if value.hasPrefix("[mvk-info]") { return false }
            if value.hasPrefix("\t") && value.contains("GPU") { return false }
            if value.hasPrefix("VK_") { return false }
            if value.contains("MoltenVK version") { return false }
            if value.contains("Native Crash Reporting") { return false }
            if value.contains("Got a UNKNOWN while executing native code") { return false }
            return true
        }
        let body = filtered.suffix(40).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            return body
        }
        return String(text.suffix(2000)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runPackager(
        packagerURL: URL,
        wineURL: URL?,
        stagingURL: URL,
        outputURL: URL,
        packageBaseName: String,
        log: BuildMessageLog
    ) throws -> URL {
        let resolvedPackager = resolvePackagerExecutable(packagerURL)
        let workDirectory = EmbeddedRuntime.packagerWorkingDirectory(for: resolvedPackager)
        let isWindowsExecutable = resolvedPackager.pathExtension.lowercased() == "exe"
        let searchRoots = packageSearchRoots(
            outputURL: outputURL,
            stagingURL: stagingURL,
            extra: isWindowsExecutable ? [workDirectory] : []
        )
        let before = packageFileRecords(under: searchRoots)
        let completion = PackagerCompletionGate(before: before) {
            self.packageFileRecords(under: searchRoots)
        }
        let result: (status: Int32, output: String)
        if isWindowsExecutable {
            guard let wineRuntime = EmbeddedRuntime.resolveWine(userOverride: wineURL) else {
                throw BuilderError.wineRuntimeMissing
            }
            try validateRosetta(for: wineRuntime)
            log.append("Starting Wine (often 10–30 seconds on Apple Silicon; first run can take longer)…")
            log.append("Invoking \(resolvedPackager.lastPathComponent) from \(workDirectory.path).")
            result = try runWineProcess(
                runtime: wineRuntime,
                arguments: [resolvedPackager.path, "-C", outputURL.path, stagingURL.path],
                currentDirectory: workDirectory,
                streamLine: { line in
                    completion.note(line)
                    self.appendPackagerStreamLine(line, to: log)
                },
                isComplete: {
                    completion.isFinished()
                }
            )
        } else {
            result = try runProcess(
                executable: resolvedPackager.path,
                arguments: [stagingURL.path],
                currentDirectory: workDirectory
            )
        }

        let produced = completion.producedPackages()
        let outputText = sanitizedProcessOutput(result.output)
        if result.status != 0, produced.isEmpty {
            if resolvedPackager.lastPathComponent.lowercased() == "make_pkg.exe" {
                throw BuilderError.packagerFailed(
                    outputText + "\n\nThe .NET make_pkg.exe front-end often crashes under Wine on macOS. Use kit/psn_package_npdrm.exe instead (the app selects it automatically in release builds)."
                )
            }
            throw BuilderError.packagerFailed(outputText)
        }
        if result.status != 0 {
            log.append("Package builder finished writing the .pkg; closed the Wine process.")
        } else if !isWindowsExecutable, !outputText.isEmpty {
            log.append(outputText)
        }

        guard let packageURL = produced.sorted(by: { $0.path < $1.path }).first else {
            throw BuilderError.packageNotProduced(outputURL)
        }
        if packageURL.deletingLastPathComponent().path != outputURL.path {
            log.append("Packager wrote \(packageURL.lastPathComponent) under \(packageURL.deletingLastPathComponent().path) (Wine ignores -C here); copying to your output folder.")
        }
        let destination = outputURL.appendingPathComponent("\(packageBaseName).pkg")
        if packageURL.path != destination.path {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: packageURL, to: destination)
            let producedParent = packageURL.deletingLastPathComponent().standardizedFileURL.path
            let outputParent = outputURL.standardizedFileURL.path
            let workParent = workDirectory.standardizedFileURL.path
            if producedParent == outputParent || (isWindowsExecutable && producedParent == workParent) {
                try fileManager.removeItem(at: packageURL)
            }
        }
        log.append("Package builder produced \(destination.lastPathComponent).")
        return destination
    }

    private func packageSearchRoots(outputURL: URL, stagingURL: URL, extra: [URL] = []) -> [URL] {
        let roots = [outputURL, stagingURL] + extra
        var seen = Set<String>()
        return roots.filter { seen.insert($0.path).inserted }
    }

    private func packageFileRecords(under urls: [URL]) -> [PackageFileRecord] {
        urls.flatMap { packageFileRecords(under: $0) }
    }

    private func packageFileRecords(under url: URL) -> [PackageFileRecord] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return enumerator?.compactMap { item in
            guard let candidate = item as? URL,
                  candidate.pathExtension.lowercased() == "pkg" else { return nil }
            let attributes = try? fileManager.attributesOfItem(atPath: candidate.path)
            let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
            let modified = attributes?[.modificationDate] as? Date ?? .distantPast
            return PackageFileRecord(url: candidate, size: size, modified: modified)
        } ?? []
    }

    private func appendPackagerStreamLine(_ line: String, to log: BuildMessageLog) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if trimmed.hasPrefix("[mvk-info]") { return }
        if trimmed.hasPrefix("VK_") { return }
        if trimmed.contains("MoltenVK version") { return }
        if trimmed.contains("GPU Family") { return }
        if trimmed == "%" || trimmed.allSatisfy({ $0 == "%" || $0.isWhitespace }) { return }
        if trimmed.unicodeScalars.allSatisfy({ $0 == "%" || CharacterSet.decimalDigits.contains($0) }) {
            return
        }
        log.append(trimmed)
    }

    private func replaceItem(_ source: URL, destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private func safeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        let result = String(scalars)
        return result.isEmpty ? "amiga-disk" : result
    }

    private func align4(_ value: UInt32) -> UInt32 {
        (value + 3) & ~3
    }

    private func resolveToolExecutable(preferred: URL?, names: [String]) -> String? {
        if let preferred, fileManager.isExecutableFile(atPath: preferred.path) {
            return preferred.path
        }
        return findExecutable(named: names)
    }

    private func findExecutable(named names: [String]) -> String? {
        let searchPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        for name in names {
            for path in searchPaths {
                let candidate = URL(fileURLWithPath: path).appendingPathComponent(name)
                if fileManager.isExecutableFile(atPath: candidate.path) {
                    return candidate.path
                }
            }
        }
        return nil
    }

    private func resolvePackagerExecutable(_ packagerURL: URL) -> URL {
        let name = packagerURL.lastPathComponent.lowercased()
        if name == "make_pkg.exe" {
            let root = packagerURL.deletingLastPathComponent()
            if let replacement = EmbeddedRuntime.preferredConsolePackager(in: root),
               replacement.lastPathComponent.lowercased() == "psn_package_npdrm.exe" {
                return replacement
            }
        }
        return packagerURL
    }

    private func validateRosetta(for runtime: WineRuntime) throws {
        if runtime.requiresRosetta && !EmbeddedRuntime.rosettaIsInstalled() {
            throw BuilderError.rosettaRequired
        }
    }

    private func ensureWinePrefix(at url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func runWineProcess(
        runtime: WineRuntime,
        arguments: [String],
        currentDirectory: URL?,
        input: String? = nil,
        streamLine: ((String) -> Void)? = nil,
        isComplete: (() -> Bool)? = nil
    ) throws -> (status: Int32, output: String) {
        try ensureWinePrefix(at: runtime.prefixURL)
        var environment = ProcessInfo.processInfo.environment
        environment["WINEPREFIX"] = runtime.prefixURL.path
        environment["WINEDEBUG"] = environment["WINEDEBUG"] ?? "-all"
        environment["PATH"] = runtime.binDirectory.path + ":" + (environment["PATH"] ?? "")
        if runtime.requiresRosetta {
            return try runProcess(
                executable: "/usr/bin/arch",
                arguments: ["-x86_64", runtime.executable.path] + arguments,
                currentDirectory: currentDirectory,
                input: input,
                environment: environment,
                streamLine: streamLine,
                isComplete: isComplete
            )
        }
        return try runProcess(
            executable: runtime.executable.path,
            arguments: arguments,
            currentDirectory: currentDirectory,
            input: input,
            environment: environment,
            streamLine: streamLine,
            isComplete: isComplete
        )
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        currentDirectory: URL?,
        input: String? = nil,
        environment: [String: String]? = nil,
        streamLine: ((String) -> Void)? = nil,
        isComplete: (() -> Bool)? = nil
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        let inputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = inputPipe
        if let environment {
            process.environment = environment
        }
        process.currentDirectoryURL = currentDirectory

        let sync = NSLock()
        var collected = Data()
        var lineRemainder = ""

        func consume(_ chunk: Data) -> [String] {
            guard !chunk.isEmpty else { return [] }
            sync.lock()
            collected.append(chunk)
            var lines: [String] = []
            if streamLine != nil, let text = String(data: chunk, encoding: .utf8) {
                let combined = lineRemainder + text
                let segments = combined.split(separator: "\n", omittingEmptySubsequences: false)
                if combined.hasSuffix("\n") {
                    lineRemainder = ""
                    lines = segments.dropLast().map(String.init)
                } else if segments.count > 1 {
                    lines = segments.dropLast().map(String.init)
                    lineRemainder = String(segments.last ?? "")
                } else {
                    lineRemainder = combined
                }
            }
            sync.unlock()
            return lines
        }

        pipe.fileHandleForReading.readabilityHandler = { handle in
            sync.lock()
            let chunk = handle.availableData
            sync.unlock()
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            for line in consume(chunk) {
                streamLine?(line)
            }
        }

        try process.run()
        if let input {
            inputPipe.fileHandleForWriting.write(Data(input.utf8))
            inputPipe.fileHandleForWriting.closeFile()
        } else if isComplete == nil {
            inputPipe.fileHandleForWriting.closeFile()
        }

        var sentEnterAfterComplete = false
        var completedAt: Date?
        if let isComplete {
            while process.isRunning {
                if isComplete() {
                    if completedAt == nil {
                        completedAt = Date()
                    }
                    if !sentEnterAfterComplete, input == nil {
                        sentEnterAfterComplete = true
                        try? inputPipe.fileHandleForWriting.write(contentsOf: Data("\n".utf8))
                        try? inputPipe.fileHandleForWriting.close()
                    }
                    if let completedAt, Date().timeIntervalSince(completedAt) >= 1.5 {
                        terminateProcess(process)
                        break
                    }
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }

        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        if input == nil, !sentEnterAfterComplete {
            try? inputPipe.fileHandleForWriting.close()
        }
        sync.lock()
        let leftover = pipe.fileHandleForReading.readDataToEndOfFile()
        sync.unlock()
        for line in consume(leftover) {
            streamLine?(line)
        }
        sync.lock()
        let remainder = lineRemainder
        lineRemainder = ""
        let outputData = collected
        sync.unlock()
        if !remainder.isEmpty {
            streamLine?(remainder)
        }
        return (
            process.terminationStatus,
            String(data: outputData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    private func terminateProcess(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}

private struct PackageFileRecord {
    let url: URL
    let size: UInt64
    let modified: Date
}

/// `psn_package_npdrm.exe` prints the DRM notice and then often sits in Wine
/// instead of exiting. Treat a finished .pkg plus that notice as success.
private final class PackagerCompletionGate {
    private let lock = NSLock()
    private let before: [String: PackageFileRecord]
    private let listPackages: () -> [PackageFileRecord]
    private var sawNotice = false
    private var stableCandidate: (path: String, size: UInt64, since: Date)?

    init(before: [PackageFileRecord], listPackages: @escaping () -> [PackageFileRecord]) {
        self.before = Dictionary(before.map { ($0.url.path, $0) }, uniquingKeysWith: { _, last in last })
        self.listPackages = listPackages
    }

    func note(_ line: String) {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard text.contains("please use npdrm edata") || text.contains("not protected by drm") else {
            return
        }
        lock.lock()
        sawNotice = true
        lock.unlock()
    }

    func isFinished() -> Bool {
        let produced = producedRecords()
        lock.lock()
        defer { lock.unlock() }
        if sawNotice, !produced.isEmpty {
            return true
        }
        guard let pkg = produced.sorted(by: { $0.url.path < $1.url.path }).first else {
            stableCandidate = nil
            return false
        }
        if let candidate = stableCandidate, candidate.path == pkg.url.path, candidate.size == pkg.size, pkg.size > 0 {
            return Date().timeIntervalSince(candidate.since) >= 2
        }
        stableCandidate = (pkg.url.path, pkg.size, Date())
        return false
    }

    func producedPackages() -> [URL] {
        producedRecords().map(\.url)
    }

    private func producedRecords() -> [PackageFileRecord] {
        listPackages().filter { record in
            guard let previous = before[record.url.path] else { return record.size > 0 }
            return record.modified > previous.modified || record.size != previous.size
        }
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}

// MARK: - SwiftUI

@MainActor
final class BuilderViewModel: ObservableObject {
    enum FileTarget {
        case icon
        case background
        case video
        case music
        case ebootELF
        case resigner
        case packager
        case wine
    }

    @Published var inputs: [URL] = []
    @Published var title = "Amiga Game"
    @Published var titleID = "AMIG00001"
    @Published var contentID = "JP9000-AMIG00001_00-0000000000000000"
    @Published var appVersion = "01.00"
    @Published var ps3SystemVersion = "01.8000"
    @Published var templatePath = ""
    @Published var outputPath = ""
    @Published var iconPath = ""
    @Published var backgroundPath = ""
    @Published var videoPath = ""
    @Published var musicPath = ""
    @Published var ebootELFPath = ""
    @Published var sourceELFIdentifier = "MAGICS500"
    @Published var resignerPath = ""
    @Published var resignEboot = true
    @Published var packagerPath = ""
    @Published var winePath = ""
    @Published var debug = false
    @Published var log = "Ready. Add an Amiga disk image to begin.\n"
    @Published var isBusy = false
    @Published var iconCropSourceURL: URL?
    @Published var backgroundCropSourceURL: URL?
    @Published var showIconCropSheet = false
    @Published var showBackgroundCropSheet = false
    @Published var showMusicPreview = false
    @Published var artworkAlertMessage: String?
    private var contentIDTitleID = "AMIG00001"
    private var metadataLockedToInput = true
    private var isApplyingInputMetadata = false

    init() {
        let fileManager = FileManager.default
        if let template = EmbeddedRuntime.templateURL() {
            templatePath = template.path
        }
        if let defaultELF = EmbeddedRuntime.ebootELFSource() {
            ebootELFPath = defaultELF.path
        }
        if let defaultResigner = EmbeddedRuntime.resignerExecutable() {
            resignerPath = defaultResigner.path
        }
        if let packager = EmbeddedRuntime.packagerExecutable() {
            packagerPath = packager.path
        }
        if let wine = EmbeddedRuntime.resolveWine(userOverride: nil) {
            winePath = wine.executable.path
        }
        outputPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Amiga-PS3-pkgs", isDirectory: true)
            .path
        try? fileManager.createDirectory(
            atPath: outputPath,
            withIntermediateDirectories: true
        )
        applyEmbeddedDefaultsForResign()

        // Optional command-line input keeps scripted demos and recordings
        // deterministic while the normal UI remains available for adding
        // files interactively.
        if let inputPath = commandLineValue("--input") {
            let inputURL = URL(fileURLWithPath: inputPath)
            if FileManager.default.fileExists(atPath: inputURL.path) {
                inputs = [inputURL]
                applyMetadataFromPrimaryInput(inputURL)
            }
        }
        if commandLineValue("--title") != nil
            || commandLineValue("--title-id") != nil
            || commandLineValue("--content-id") != nil {
            metadataLockedToInput = false
        }
        title = commandLineValue("--title") ?? title
        titleID = commandLineValue("--title-id") ?? titleID
        contentID = commandLineValue("--content-id") ?? contentID
        appVersion = commandLineValue("--app-version") ?? appVersion
        ps3SystemVersion = commandLineValue("--ps3-version") ?? ps3SystemVersion
        templatePath = commandLineValue("--template") ?? templatePath
        outputPath = commandLineValue("--output") ?? outputPath
        iconPath = commandLineValue("--icon") ?? iconPath
        backgroundPath = commandLineValue("--background") ?? backgroundPath
        videoPath = commandLineValue("--video") ?? videoPath
        musicPath = commandLineValue("--music") ?? musicPath
        ebootELFPath = commandLineValue("--eboot-elf") ?? ebootELFPath
        sourceELFIdentifier = commandLineValue("--elf-identifier") ?? sourceELFIdentifier
        resignerPath = commandLineValue("--resigner") ?? resignerPath
        packagerPath = commandLineValue("--packager") ?? packagerPath
        winePath = commandLineValue("--wine") ?? winePath
        debug = CommandLine.arguments.contains("--debug")
    }

    var effectiveTemplatePath: String {
        let trimmed = templatePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, FileManager.default.fileExists(atPath: trimmed) {
            return trimmed
        }
        return EmbeddedRuntime.templateURL()?.path ?? ""
    }

    var canPrepare: Bool {
        !inputs.isEmpty && !effectiveTemplatePath.isEmpty && !outputPath.isEmpty && !isBuildInProgress
    }

    /// The build log is the source of truth. A leftover busy flag must not
    /// keep the button spinning after "Done." or "ERROR:" is already shown.
    var isBuildInProgress: Bool {
        if log.contains("\n\nDone.") || log.contains("\n\nERROR:") {
            return false
        }
        return isBusy || log.hasPrefix("Building PS3 package…")
    }

    func applyEmbeddedDefaultsForResign() {
        if resignerPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let resigner = EmbeddedRuntime.resignerExecutable() {
            resignerPath = resigner.path
        }
        if ebootELFPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let elf = EmbeddedRuntime.ebootELFSource() {
            ebootELFPath = elf.path
        }
        if winePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let wine = EmbeddedRuntime.resolveWine(userOverride: nil) {
            winePath = wine.executable.path
        }
    }

    var effectiveResignerPath: String {
        let trimmed = resignerPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, FileManager.default.fileExists(atPath: trimmed) {
            return trimmed
        }
        return EmbeddedRuntime.resignerExecutable()?.path ?? trimmed
    }

    var effectiveEbootELFPath: String {
        let trimmed = ebootELFPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, FileManager.default.fileExists(atPath: trimmed) {
            return trimmed
        }
        return EmbeddedRuntime.ebootELFSource()?.path ?? trimmed
    }

    var effectiveWinePath: String {
        let trimmed = winePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty,
           FileManager.default.isExecutableFile(atPath: trimmed) {
            return trimmed
        }
        return EmbeddedRuntime.resolveWine(userOverride: nil)?.executable.path ?? trimmed
    }

    var effectivePackagerPath: String {
        let trimmed = packagerPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let url = URL(fileURLWithPath: trimmed)
            if url.lastPathComponent.lowercased() == "make_pkg.exe" {
                let root = url.deletingLastPathComponent()
                if let replacement = EmbeddedRuntime.preferredConsolePackager(in: root) {
                    return replacement.path
                }
            }
            return trimmed
        }
        return EmbeddedRuntime.packagerExecutable()?.path ?? ""
    }

    var canBuildPackage: Bool {
        packageBlockedReason == nil
    }

    var packageBlockedReason: String? {
        if inputs.isEmpty {
            return "Add an Amiga ADF, HDF, or LHA file."
        }
        if effectiveTemplatePath.isEmpty {
            return "The CLIKAK500 emulator template was not found."
        }
        if outputPath.isEmpty {
            return "Choose an output folder."
        }
        let packager = effectivePackagerPath
        if packager.isEmpty {
            return "The Windows package builder was not found."
        }
        if packager.lowercased().hasSuffix(".exe"),
           EmbeddedRuntime.resolveWine(userOverride: urlOrNil(effectiveWinePath)) == nil {
            return "Wine is required to run the Windows package builder."
        }
        if isBuildInProgress {
            return "A build is already running."
        }
        return nil
    }

    func syncContentID(with newTitleID: String) {
        let previousDefault = "JP9000-\(contentIDTitleID)_00-0000000000000000"
        if contentID == previousDefault {
            contentID = "JP9000-\(newTitleID.uppercased())_00-0000000000000000"
        }
        contentIDTitleID = newTitleID
    }

    func addInputs() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        // Some Amiga files use custom extensions that macOS does not map to a
        // registered UTI. Keep the picker open to all files and validate the
        // extension in the builder instead of making valid ADF/HDF/LHA files
        // appear disabled in the panel.
        panel.allowedContentTypes = []
        if panel.runModal() == .OK {
            inputs.append(contentsOf: panel.urls.filter { !inputs.contains($0) })
            if let first = inputs.first {
                applyMetadataFromPrimaryInput(first)
            }
            refreshReadyStateLog()
        }
    }

    func applyMetadataFromPrimaryInput(_ url: URL) {
        guard metadataLockedToInput else { return }
        isApplyingInputMetadata = true
        defer { isApplyingInputMetadata = false }
        title = inferredTitle(from: url)
        let inferredID = inferredTitleID(from: url)
        titleID = inferredID
        contentID = "JP9000-\(inferredID)_00-0000000000000000"
        contentIDTitleID = inferredID
    }

    func inputsDidChange() {
        if let first = inputs.first {
            applyMetadataFromPrimaryInput(first)
        }
        refreshReadyStateLog()
    }

    func refreshReadyStateLog() {
        let idlePrefixes = ["Ready.", "Added ", "Ready to create"]
        let firstLine = log.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? log
        guard !isBuildInProgress, idlePrefixes.contains(where: { firstLine.hasPrefix($0) }) else { return }
        if inputs.isEmpty {
            log = "Ready. Add an Amiga disk image to begin.\n"
        } else if let reason = packageBlockedReason {
            log = "Added \(inputs.map(\.lastPathComponent).joined(separator: ", ")). \(reason)\n"
        } else {
            log = "Ready to create a .pkg from \(inputs.map(\.lastPathComponent).joined(separator: ", ")).\n"
        }
    }

    func userEditedMetadata() {
        guard !isApplyingInputMetadata else { return }
        metadataLockedToInput = false
    }

    func chooseFile(for target: FileTarget, allowed: [String]) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = allowed.compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK, let url = panel.url {
            switch target {
            case .icon: iconPath = url.path
            case .background: backgroundPath = url.path
            case .video: videoPath = url.path
            case .music: musicPath = url.path
            case .ebootELF: ebootELFPath = url.path
            case .resigner: resignerPath = url.path
            case .packager: packagerPath = url.path
            case .wine: winePath = url.path
            }
        }
    }

    func chooseFolder(for target: FolderTarget) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            switch target {
            case .template:
                templatePath = resolvedTemplatePath(from: url)
            case .output:
                outputPath = url.path
            }
            refreshReadyStateLog()
        }
    }

    enum FolderTarget {
        case template
        case output
    }

    func buildPackage() {
        run(makePackage: true)
    }

    func appendLogLine(_ line: String) {
        guard isBusy,
              !log.contains("\n\nDone."),
              !log.contains("\n\nERROR:") else { return }
        if log.isEmpty {
            log = line
        } else if log.hasSuffix("\n") {
            log += line
        } else {
            log += "\n" + line
        }
        if !log.hasSuffix("\n") {
            log += "\n"
        }
    }

    private func run(makePackage: Bool) {
        guard canPrepare else {
            log = "Cannot start: add an Amiga input, choose the template folder, and choose an output folder.\n"
            return
        }
        if resignEboot {
            applyEmbeddedDefaultsForResign()
        }
        let options = BuildOptions(
            inputs: inputs,
            title: title,
            titleID: titleID,
            contentID: contentID,
            appVersion: appVersion,
            ps3SystemVersion: ps3SystemVersion,
            templateURL: URL(fileURLWithPath: effectiveTemplatePath),
            outputURL: URL(fileURLWithPath: outputPath),
            iconURL: urlOrNil(iconPath),
            backgroundURL: urlOrNil(backgroundPath),
            backgroundVideoURL: urlOrNil(videoPath),
            musicURL: urlOrNil(musicPath),
            ebootELFURL: urlOrNil(effectiveEbootELFPath),
            sourceELFIdentifier: sourceELFIdentifier,
            resignerURL: urlOrNil(effectiveResignerPath),
            resignEboot: resignEboot,
            packagerURL: urlOrNil(effectivePackagerPath),
            wineURL: urlOrNil(effectiveWinePath),
            debug: debug
        )
        let header = "Building PS3 package…"
        isBusy = true
        log = header + "\n"

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let viewModel = self else { return }
            let outcome: Result<BuildResult, Error>
            do {
                let result = try PS3PackageBuilder().run(options: options, makePackage: makePackage) { line in
                    Task { @MainActor in
                        viewModel.appendLogLine(line)
                    }
                }
                outcome = .success(result)
            } catch {
                outcome = .failure(error)
            }
            let finishedLog: String
            switch outcome {
            case .success(let result):
                finishedLog = header + "\n" + result.messages.joined(separator: "\n") + "\n\nDone."
            case .failure(let error):
                finishedLog = header + "\n\nERROR: \(error.localizedDescription)\n"
            }
            await viewModel.finishBuild(with: finishedLog)
        }
    }

    @MainActor
    private func finishBuild(with finishedLog: String) {
        log = finishedLog
        isBusy = false
        objectWillChange.send()
    }

    private func urlOrNil(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : URL(fileURLWithPath: trimmed)
    }

    private func resolvedTemplatePath(from url: URL) -> String {
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("USRDIR/EBOOT.BIN").path) {
            return url.path
        }
        let nested = url.appendingPathComponent("CLIKAK500", isDirectory: true)
        if FileManager.default.fileExists(atPath: nested.appendingPathComponent("USRDIR/EBOOT.BIN").path) {
            return nested.path
        }
        return url.path
    }

    private func commandLineValue(_ name: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: name),
              CommandLine.arguments.indices.contains(index + 1)
        else {
            return nil
        }
        return CommandLine.arguments[index + 1]
    }

    private func inferredTitle(from url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private func inferredTitleID(from url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent.uppercased()
        let filtered = stem.unicodeScalars.filter {
            ($0.value >= 48 && $0.value <= 57) || ($0.value >= 65 && $0.value <= 90)
        }
        var id = String(String.UnicodeScalarView(filtered))
        if id.isEmpty {
            id = "AMIGAME01"
        }
        if id.count > 9 {
            id = String(id.prefix(9))
        }
        while id.count < 9 {
            id.append("0")
        }
        return id
    }
}

struct FileRow: View {
    let url: URL
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "opticaldisc")
                .foregroundStyle(.secondary)
            Text(url.lastPathComponent)
                .lineLimit(1)
            Spacer()
            Button("Remove", action: onRemove)
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
        }
        .padding(.vertical, 2)
    }
}

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct BuildLogPanel: View {
    let text: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text.isEmpty ? " " : text)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
                    .id("buildLogBottom")
            }
            .frame(minHeight: 180)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )
            .onChange(of: text) { _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("buildLogBottom", anchor: .bottom)
                }
            }
        }
    }
}

struct PathPicker: View {
    let label: String
    @Binding var path: String
    let choose: () -> Void

    var body: some View {
        HStack {
            TextField(label, text: $path)
                .textFieldStyle(.roundedBorder)
            Button("Choose…", action: choose)
        }
    }
}

struct ContentView: View {
    @StateObject private var model = BuilderViewModel()
    @State private var showBuildLog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Amiga → PS3 Package Builder")
                        .font(.largeTitle.bold())
                    Text("Create an installable PS3 package from an Amiga disk image.")
                        .foregroundStyle(.secondary)
                }

                Card(title: "1. Amiga input") {
                    HStack {
                        Button {
                            model.addInputs()
                        } label: {
                            Label("Add ADF / HDF / LHA", systemImage: "plus")
                        }
                        Spacer()
                        Text("LHA archives must contain an ADF or HDF.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if model.inputs.isEmpty {
                        Text("No input selected.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.inputs, id: \.self) { input in
                            FileRow(url: input) {
                                model.inputs.removeAll { $0 == input }
                                model.inputsDidChange()
                            }
                        }
                    }
                }

                Card(title: "2. PS3 metadata") {
                    LabeledContent("Title") {
                        TextField("Displayed XMB title", text: $model.title)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: model.title) { _ in model.userEditedMetadata() }
                    }
                    LabeledContent("Title ID") {
                        TextField("Exactly 9 uppercase letters/digits", text: $model.titleID)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: model.titleID) { _ in model.userEditedMetadata() }
                    }
                    LabeledContent("Content ID") {
                        TextField("JP9000-TITLEID_00-0000000000000000", text: $model.contentID)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: model.contentID) { _ in model.userEditedMetadata() }
                    }
                    LabeledContent("Version") {
                        TextField("01.00", text: $model.appVersion)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Minimum PS3 system") {
                        TextField("01.8000", text: $model.ps3SystemVersion)
                            .textFieldStyle(.roundedBorder)
                    }
                    Text("Title ID and Content ID are filled from the Amiga filename when you add input. EBOOT resign uses TrueAncestor with the Content ID shown here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Card(title: "3. Output") {
                    PathPicker(
                        label: "Package output folder",
                        path: $model.outputPath
                    ) {
                        model.chooseFolder(for: .output)
                    }
                    if model.effectiveTemplatePath.isEmpty {
                        HStack(alignment: .top) {
                            Text("The CLIKAK500 emulator template was not found. Choose the tutorial folder that contains CLIKAK500, or rebuild the app bundle with tutorial assets.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Button("Choose template…") {
                                model.chooseFolder(for: .template)
                            }
                        }
                    }
                    Toggle("Debug", isOn: $model.debug)
                    Text(model.debug
                        ? "Keeps a \(model.titleID)_debug folder of the package assets and names the package \(model.titleID)_debug.pkg."
                        : "Writes \(model.titleID).pkg only. The asset folder is not kept.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Card(title: "4. Artwork and sound (optional)") {
                    ArtworkAssetRow(
                        title: "Game icon (ICON0.PNG)",
                        spec: .icon0,
                        exportedPath: $model.iconPath,
                        cropSourceURL: $model.iconCropSourceURL,
                        showCropSheet: $model.showIconCropSheet,
                        alertMessage: $model.artworkAlertMessage
                    )
                    Divider()
                    ArtworkAssetRow(
                        title: "Background art (PIC1.PNG)",
                        spec: .pic1,
                        exportedPath: $model.backgroundPath,
                        cropSourceURL: $model.backgroundCropSourceURL,
                        showCropSheet: $model.showBackgroundCropSheet,
                        alertMessage: $model.artworkAlertMessage
                    )
                    Divider()
                    MusicAssetRow(musicPath: $model.musicPath, showPreview: $model.showMusicPreview)
                    Text("Leave artwork empty to keep the template ICON0/PIC1. Custom music is converted to SND0.AT3 during the build.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Card(title: "Build log") {
                    DisclosureGroup(isExpanded: $showBuildLog) {
                        VStack(alignment: .leading, spacing: 8) {
                            BuildLogPanel(text: model.log)
                            if model.isBuildInProgress {
                                Text("Working… new lines appear here as each step completes.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text(showBuildLog ? "Hide log" : "Show log")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button {
                        model.buildPackage()
                    } label: {
                        Label(model.isBuildInProgress ? "Creating .PKG" : "Create .PKG", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("b", modifiers: [.command])
                    .disabled(!model.canBuildPackage)

                    if model.isBuildInProgress {
                        Text("Creating…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let reason = model.packageBlockedReason {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 820, minHeight: 760)
        .onChange(of: model.titleID) { newValue in
            model.syncContentID(with: newValue)
        }
        .sheet(isPresented: $model.showIconCropSheet) {
            if let source = model.iconCropSourceURL {
                ImageCropSheet(
                    sourceURL: source,
                    spec: .icon0,
                    onConfirm: { url in
                        model.iconPath = url.path
                        model.showIconCropSheet = false
                        model.iconCropSourceURL = nil
                    },
                    onCancel: {
                        model.showIconCropSheet = false
                        model.iconCropSourceURL = nil
                    }
                )
            }
        }
        .sheet(isPresented: $model.showBackgroundCropSheet) {
            if let source = model.backgroundCropSourceURL {
                ImageCropSheet(
                    sourceURL: source,
                    spec: .pic1,
                    onConfirm: { url in
                        model.backgroundPath = url.path
                        model.showBackgroundCropSheet = false
                        model.backgroundCropSourceURL = nil
                    },
                    onCancel: {
                        model.showBackgroundCropSheet = false
                        model.backgroundCropSourceURL = nil
                    }
                )
            }
        }
        .sheet(isPresented: $model.showMusicPreview) {
            if !model.musicPath.isEmpty {
                AudioPreviewSheet(
                    audioURL: URL(fileURLWithPath: model.musicPath),
                    onClose: { model.showMusicPreview = false }
                )
            }
        }
        .alert(
            "Image too small",
            isPresented: Binding(
                get: { model.artworkAlertMessage != nil },
                set: { if !$0 { model.artworkAlertMessage = nil } }
            )
        ) {
            Button("OK") {
                model.artworkAlertMessage = nil
            }
        } message: {
            Text(model.artworkAlertMessage ?? "")
        }
    }
}

@main
struct AmigaPS3BuilderApp: App {
    init() {
        if CommandLine.arguments.contains("--self-test") {
            runSelfTest()
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }

    private func runSelfTest() {
        let template = EmbeddedRuntime.templateURL()
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Create Amiga PKG Tutorial/CLIKAK500")
        let trueAncestor = EmbeddedRuntime.trueAncestorURL()
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Create Amiga PKG Tutorial/trueancestor 1.80")
        let input = template.appendingPathComponent("USRDIR/savedisk.adf")
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("amiga-ps3-builder-self-test", isDirectory: true)
        try? FileManager.default.removeItem(at: output)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let options = BuildOptions(
            inputs: [input],
            title: "Self Test",
            titleID: "AMIG00001",
            contentID: "JP9000-AMIG00001_00-0000000000000000",
            appVersion: "01.00",
            ps3SystemVersion: "01.8000",
            templateURL: template,
            outputURL: output,
            iconURL: nil,
            backgroundURL: nil,
            backgroundVideoURL: nil,
            musicURL: nil,
            ebootELFURL: nil,
            sourceELFIdentifier: "MAGICS500",
            resignerURL: nil,
            resignEboot: false,
            packagerURL: nil,
            wineURL: nil,
            debug: false
        )
        do {
            let result = try PS3PackageBuilder().run(options: options, makePackage: false)
            print("SELF-TEST OK")
            print(result.stagingURL.path)
            print(result.messages.joined(separator: "\n"))

            let fileManager = FileManager.default
            let fakeToolchain = output.appendingPathComponent("fake-toolchain", isDirectory: true)
            try fileManager.createDirectory(at: fakeToolchain, withIntermediateDirectories: true)
            let fakeResigner = fakeToolchain.appendingPathComponent("fake-resigner.exe")
            let fakeScript = """
            #!/bin/sh
            cat >/dev/null
            cp EBOOT.ELF EBOOT.BIN
            """
            try Data(fakeScript.utf8).write(to: fakeResigner, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: fakeResigner.path
            )

            var resignOptions = options
            resignOptions.ebootELFURL = trueAncestor.appendingPathComponent("EBOOT.ELF")
            resignOptions.resignerURL = fakeResigner
            resignOptions.wineURL = URL(fileURLWithPath: "/bin/sh")
            resignOptions.resignEboot = true
            let resignResult = try PS3PackageBuilder().run(options: resignOptions, makePackage: false)
            let generatedEBOOT = resignResult.stagingURL.appendingPathComponent("USRDIR/EBOOT.BIN")
            let generatedData = try Data(contentsOf: generatedEBOOT)
            let oldIdentifier = Data("MAGICS500".utf8)
            let newIdentifier = Data("AMIG00001".utf8)
            guard generatedData.range(of: oldIdentifier) == nil,
                  generatedData.range(of: newIdentifier) != nil else {
                throw BuilderError.ebootIdentifierNotFound("self-test replacement")
            }
            print("EBOOT-SELF-TEST OK")

            let ping = URL(fileURLWithPath: "/System/Library/Sounds/Ping.aiff")
            if FileManager.default.fileExists(atPath: ping.path) {
                var musicOptions = options
                musicOptions.musicURL = ping
                let musicResult = try PS3PackageBuilder().run(options: musicOptions, makePackage: false)
                let snd0 = musicResult.stagingURL.appendingPathComponent("SND0.AT3")
                let header = try Data(contentsOf: snd0).prefix(12)
                guard header.starts(with: Data("RIFF".utf8)),
                      header.suffix(4).elementsEqual(Data("WAVE".utf8)) else {
                    throw BuilderError.at3EncodeFailed("self-test SND0.AT3 is not a RIFF WAVE ATRAC file")
                }
                print("MUSIC-SELF-TEST OK")
            }
        } catch {
            print("SELF-TEST FAILED: \(error.localizedDescription)")
        }
    }
}
