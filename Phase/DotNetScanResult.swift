import Foundation

struct DotNetScanResult: Identifiable, Hashable {
    enum Kind: String, Codable, Hashable, CaseIterable {
        case sdk
        case host
        case runtime
    }

    let id: UUID
    let version: String
    let kind: Kind
    let product: String?

    init(version: String, kind: Kind, product: String? = nil) {
        self.id = UUID()
        self.version = version
        self.kind = kind
        self.product = product
    }
}
