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

    @Test func createsSegmentsAroundVariable() {
        let segments = CommandTemplate.segments(
            of: "deploy {{service=payments}} now",
            values: ["service": "billing"]
        )

        #expect(segments == [
            CommandTemplate.Segment(text: "deploy ", variableName: nil),
            CommandTemplate.Segment(text: "billing", variableName: "service"),
            CommandTemplate.Segment(text: " now", variableName: nil)
        ])
    }

    @Test func createsSegmentsForAdjacentVariables() {
        let segments = CommandTemplate.segments(
            of: "{{first=one}}{{second=two}}",
            values: [:]
        )

        #expect(segments == [
            CommandTemplate.Segment(text: "one", variableName: "first"),
            CommandTemplate.Segment(text: "two", variableName: "second")
        ])
    }

    @Test func createsSegmentsForTemplateStartingWithVariable() {
        let segments = CommandTemplate.segments(
            of: "{{service=payments}} now",
            values: [:]
        )

        #expect(segments == [
            CommandTemplate.Segment(text: "payments", variableName: "service"),
            CommandTemplate.Segment(text: " now", variableName: nil)
        ])
    }

    @Test func createsSegmentsForTemplateEndingWithVariable() {
        let segments = CommandTemplate.segments(
            of: "deploy {{service=payments}}",
            values: [:]
        )

        #expect(segments == [
            CommandTemplate.Segment(text: "deploy ", variableName: nil),
            CommandTemplate.Segment(text: "payments", variableName: "service")
        ])
    }

    @Test func createsSegmentForVariableOnlyTemplate() {
        let segments = CommandTemplate.segments(
            of: "{{service=payments}}",
            values: [:]
        )

        #expect(segments == [
            CommandTemplate.Segment(text: "payments", variableName: "service")
        ])
    }

    @Test func createsSegmentForTemplateWithoutVariables() {
        let segments = CommandTemplate.segments(
            of: "deploy now",
            values: [:]
        )

        #expect(segments == [
            CommandTemplate.Segment(text: "deploy now", variableName: nil)
        ])
    }
}
