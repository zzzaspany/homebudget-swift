import Vapor

/// Stores uploaded invoices on disk, outside the public directory.
///
/// Invoices are financial documents, so they are never served as static files — reading one goes
/// through an authenticated route that streams it back.
struct InvoiceStorage {
    let rootPath: String

    init(application: Application) {
        rootPath =
            Environment.get("INVOICE_STORAGE_PATH")
            ?? application.directory.workingDirectory + "data/uploads"
    }

    /// Saves an upload and returns its path relative to the storage root.
    func store(_ file: File, expenseID: UUID, paymentID: UUID, on request: Request) async throws -> String {
        let relativePath = "\(expenseID.uuidString)/\(paymentID.uuidString)-\(Self.sanitize(file.filename))"
        let directory = "\(rootPath)/\(expenseID.uuidString)"

        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true)
        try await request.fileio.writeFile(file.data, at: "\(rootPath)/\(relativePath)")

        return relativePath
    }

    func absolutePath(for relativePath: String) -> String {
        "\(rootPath)/\(relativePath)"
    }

    /// Reduces an uploaded filename to a leaf name that cannot escape the storage directory.
    static func sanitize(_ filename: String) -> String {
        let leaf = filename.split(separator: "/").last.map(String.init) ?? filename
        let allowed = leaf.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "-" || scalar == "_"
                ? Character(scalar) : "_"
        }
        let sanitized = String(allowed)
        return sanitized.isEmpty || sanitized.allSatisfy { $0 == "." } ? "invoice" : sanitized
    }
}

extension Application {
    var invoiceStorage: InvoiceStorage { InvoiceStorage(application: self) }
}

extension Request {
    var invoiceStorage: InvoiceStorage { InvoiceStorage(application: application) }
}
