import SwiftUI

enum HealthStatus: String, Codable {
    case healthy
    case outOfDate
    case missing
    case unsupported
    
    var color: Color {
        switch self {
        case .healthy: return .green
        case .outOfDate: return .orange
        case .missing: return .red
        case .unsupported: return .gray
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .healthy: return .green.opacity(0.15)
        case .outOfDate: return .orange.opacity(0.15)
        case .missing: return .red.opacity(0.12)
        case .unsupported: return .gray.opacity(0.1)
        }
    }
}

struct DotNetHealthResult: Identifiable {
    let id = UUID()
    let majorVersion: Int
    let label: String
    let expectedVersion: String?
    let installedVersion: String?
    let status: HealthStatus
    
    var displayName: String {
        ".NET \(majorVersion)"
    }
    
    var statusText: String {
        switch status {
        case .healthy:
            guard let version = installedVersion else { return "Up to date" }
            return "Up to date (\(version))"
            
        case .outOfDate:
            guard let installed = installedVersion, let expected = expectedVersion else {
                return "Out of date"
            }
            return "Out of date (\(installed) → \(expected))"
            
        case .missing:
            return "Not installed"
            
        case .unsupported:
            guard let version = installedVersion else { return "No longer supported" }
            return "No longer supported (\(version))"
        }
    }
    
    var badgeColor: Color {
        switch label {
        case "Current": return .blue
        case "Previous": return .purple
        case "LTS": return .indigo
        default: return .gray
        }
    }
}
