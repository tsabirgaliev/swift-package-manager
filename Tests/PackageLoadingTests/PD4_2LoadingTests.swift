/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import Utility

import PackageDescription4
import PackageModel
import TestSupport

import PackageLoading

// FIXME: We should share the infra with other loading tests.
class PackageDescription4_2LoadingTests: XCTestCase {
    let manifestLoader = ManifestLoader(resources: Resources.default)

    private func loadManifestThrowing(
        _ contents: ByteString,
        line: UInt = #line,
        body: (Manifest) -> Void
    ) throws {
        let fs = InMemoryFileSystem()
        let manifestPath = AbsolutePath.root.appending(component: Manifest.filename)
        try fs.writeFileContents(manifestPath, bytes: contents)
        let m = try manifestLoader.load(
            package: AbsolutePath.root,
            baseURL: AbsolutePath.root.asString,
            manifestVersion: .v4_2,
            fileSystem: fs)
        if case .v4 = m.package {} else {
            return XCTFail("Invalid manfiest version")
        }
        body(m)
    }

    private func loadManifest(
        _ contents: ByteString,
        line: UInt = #line,
        body: (Manifest) -> Void
    ) {
        do {
            try loadManifestThrowing(contents, line: line, body: body)
        } catch ManifestParseError.invalidManifestFormat(let error) {
            print(error)
            XCTFail(file: #file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: #file, line: line)
        }
    }

    func testBasics() {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
                name: "Trivial",
                products: [
                    .executable(name: "tool", targets: ["tool"]),
                    .library(name: "Foo", targets: ["Foo"]),
                ],
                dependencies: [
                    .package(url: "/foo1", from: "1.0.0"),
                ],
                targets: [
                    .target(
                        name: "foo",
                        dependencies: ["dep1"]),
                    .testTarget(
                        name: "bar",
                        dependencies: ["foo"]),
                ]
            )
            """

        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.name, "Trivial")

            // Check targets.
            let targets = Dictionary(items:
                manifest.package.targets.map({ ($0.name, $0 as PackageDescription4.Target ) }))
            let foo = targets["foo"]!
            XCTAssertEqual(foo.name, "foo")
            XCTAssertFalse(foo.isTest)
            XCTAssertEqual(foo.dependencies, ["dep1"])

            let bar = targets["bar"]!
            XCTAssertEqual(bar.name, "bar")
            XCTAssertTrue(bar.isTest)
            XCTAssertEqual(bar.dependencies, ["foo"])

            // Check dependencies.
            let deps = Dictionary(items: manifest.package.dependencies.map{ ($0.url, $0) })
            XCTAssertEqual(deps["/foo1"], .package(url: "/foo1", from: "1.0.0"))

            // Check products.
            guard case .v4(let package) = manifest.package else { return XCTFail() }
            let products = Dictionary(items: package.products.map{ ($0.name, $0) })

            let tool = products["tool"]! as! PackageDescription4.Product.Executable
            XCTAssertEqual(tool.name, "tool")
            XCTAssertEqual(tool.targets, ["tool"])

            let fooProduct = products["Foo"]! as! PackageDescription4.Product.Library
            XCTAssertEqual(fooProduct.name, "Foo")
            XCTAssertEqual(fooProduct.type, nil)
            XCTAssertEqual(fooProduct.targets, ["Foo"])
        }
    }

    func testSwiftLanguageVersions() throws {
        // Ensure integer values are not accepted.
        var stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               swiftLanguageVersions: [3, 4]
            )
            """

        do {
            try loadManifestThrowing(stream.bytes) { _ in }
            XCTFail()
        } catch {
            guard case let ManifestParseError.invalidManifestFormat(output) = error else {
                return XCTFail()
            }
            XCTAssertMatch(output, .and(.contains("expected element type"), .contains("SwiftVersion")))
        }

        // Check when Swift language versions is empty.
        stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               swiftLanguageVersions: []
            )
            """
        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.package.swiftLanguageVersions, [])
        }

        stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               swiftLanguageVersions: [.v3, .v4, .v4_2, .version("5")]
            )
            """
        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(
                manifest.package.swiftLanguageVersions,
                [.v3, .v4, .v4_2, SwiftLanguageVersion(string: "5")!]
            )
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testSwiftLanguageVersions", testSwiftLanguageVersions),
    ]
}
