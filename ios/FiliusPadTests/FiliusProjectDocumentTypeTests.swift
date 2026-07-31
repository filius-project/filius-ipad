import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import FiliusPad

final class FiliusProjectDocumentTypeTests: XCTestCase {
    func testRegularFileImportPolicyFailsClosed() {
        let cases: [(isRegularFile: Bool?, expected: Bool)] = [
            (true, true),
            (false, false),
            (nil, false),
        ]

        for testCase in cases {
            XCTAssertEqual(
                FiliusProjectImportResourcePolicy.accepts(
                    isRegularFile: testCase.isRegularFile
                ),
                testCase.expected,
                "isRegularFile=\(String(describing: testCase.isRegularFile))"
            )
        }
    }

    func testImportPickerAcceptsExternalFLSProvidersWithoutTrustingTheirUTType() {
        XCTAssertTrue(FiliusProjectImportResourcePolicy.allowedContentTypes.contains(.filiusProjectArchive))
        XCTAssertTrue(FiliusProjectImportResourcePolicy.allowedContentTypes.contains(.data))

        XCTAssertTrue(
            FiliusProjectImportResourcePolicy.accepts(
                fileURL: URL(fileURLWithPath: "/tmp/Filius-2-project.FLS")
            )
        )
        XCTAssertFalse(
            FiliusProjectImportResourcePolicy.accepts(
                fileURL: URL(fileURLWithPath: "/tmp/not-a-project.zip")
            )
        )
    }

    func testSaveDocumentKeepsThePreparedFLSArchiveBytes() {
        let archiveData = Data([0x50, 0x4B, 0x03, 0x04, 0x01, 0x02])
        let document = FiliusProjectFileDocument(archiveData: archiveData)

        XCTAssertEqual(document.archiveData, archiveData)
        XCTAssertEqual(FiliusProjectFileDocument.writableContentTypes, [.filiusProjectArchive])
    }

    func testFiliusProjectArchiveUsesStableExportedTypeConformingToZip() {
        XCTAssertEqual(UTType.filiusProjectArchive.identifier, "com.filius.pad.fls")
        XCTAssertNotEqual(UTType.filiusProjectArchive, .zip)
        XCTAssertTrue(UTType.filiusProjectArchive.conforms(to: .zip))
    }
}
