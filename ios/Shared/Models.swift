import Foundation

struct ApprovalOption: Codable, Identifiable, Hashable {
    var id: String { key }
    let key: String        // e.g., "1", "2", "3", "4", "5", "y", "n"
    let label: String      // e.g., "Yes, allow this time"
    let isPrimary: Bool
    let isDestructive: Bool
}

struct ApprovalRequest: Codable, Identifiable, Hashable {
    let id: String
    let agent: String
    let type: String
    let title: String
    let command: String
    let description: String
    let risk: String // "low", "medium", "high"
    let time: String
    let optionsList: [ApprovalOption]?
    let options: [String]?
    
    var dynamicOptions: [ApprovalOption] {
        if let list = optionsList, !list.isEmpty {
            return list
        }
        // Fallback default options
        return [
            ApprovalOption(key: "approve", label: "Approve", isPrimary: true, isDestructive: false),
            ApprovalOption(key: "reject", label: "Reject", isPrimary: false, isDestructive: true)
        ]
    }
}

struct HistoricalRequest: Identifiable, Codable, Hashable {
    var id: String { requestId + "_" + action }
    let requestId: String
    let agent: String
    let command: String
    let action: String // "Approved", "Rejected", "Cancelled", "Option 1", etc.
    let timestamp: Date
}
