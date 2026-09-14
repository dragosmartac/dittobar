import Foundation

struct CheatCommand: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let command: String
    let language: String
}

struct CheatSheet: Identifiable, Equatable {
    let id: String
    let title: String
    let commands: [CheatCommand]
    let sourceURL: URL
}
