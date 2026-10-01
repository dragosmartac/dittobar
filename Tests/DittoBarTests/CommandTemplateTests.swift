import Testing
@testable import DittoBar

struct CommandTemplateTests {
    @Test func findsPlaceholderOccurrences() {
        let template = "deploy {{service=payments}} to {{environment}}"

        let placeholders = CommandTemplate.placeholders(in: template)

        #expect(placeholders.map(\.name) == ["service", "environment"])
        #expect(placeholders.map(\.defaultValue) == ["payments", ""])
        #expect(placeholders.map { String(template[$0.range]) } == [
            "{{service=payments}}",
            "{{environment}}"
        ])
    }

    @Test func extractsPlaceholderNamesAndDefaults() {
        let template = "deploy {{service.name=payments api}} to {{environment-name}} ({{environment-name}})"

        let variables = CommandTemplate.variables(in: template)

        #expect(variables == [
            CommandVariable(name: "service.name", defaultValue: "payments api"),
            CommandVariable(name: "environment-name", defaultValue: "")
        ])
    }

    @Test func usesLaterDefaultForRepeatedVariable() {
        let template = "deploy {{service}} and verify {{service=payments}}"

        let variables = CommandTemplate.variables(in: template)

        #expect(variables == [
            CommandVariable(name: "service", defaultValue: "payments")
        ])
    }
}
