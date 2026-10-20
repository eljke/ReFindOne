// swift-tools-version: 5.9
import PackageDescription

/// Linux-verifiable core. The iOS app uses exactly the same source files in Xcode.
let package = Package(
    name: "ReFindOneCore",
    platforms: [.iOS(.v17)],
    products: [.library(name: "ReFindCore", targets: ["ReFindCore"])],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Modules/CSQLite"),
        .target(name: "ReFindCore", dependencies: ["CSQLite"],
                path: "ReFindOne",
                exclude: ["App", "Presentation", "Views", "Services/OCRService.swift",
                          "Services/FileImportService.swift", "Assets.xcassets", "Info.plist"],
                sources: ["Domain/CaptureItem.swift", "Domain/LinkNormalizer.swift",
                          "Data/CaptureRepository.swift", "Data/SQLiteRepository.swift",
                          "Data/AppPaths.swift", "Data/AttachmentStore.swift", "Services/BackupService.swift"]),
        .testTarget(name: "ReFindCoreTests", dependencies: ["ReFindCore"],
                    path: "Tests/ReFindCoreTests")
    ]
)
