import Testing
@testable import DittoBar

struct TextVariablesTests {
    @Test func findsPlaceholderOccurrences() {
        let raw = "deploy {{service=payments}} to {{environment}}"

        let placeholders = TextVariables.placeholders(in: raw)

        #expect(placeholders.map(\.name) == ["service", "environment"])
        #expect(placeholders.map(\.defaultValue) == ["payments", ""])
        #expect(placeholders.map { String(raw[$0.range]) } == [
            "{{service=payments}}",
            "{{environment}}"
        ])
    }

    @Test func extractsPlaceholderNamesAndDefaults() {
        let raw = "deploy {{service.name=payments api}} to {{environment-name}} ({{environment-name}})"

        let variables = TextVariables.variables(in: raw)

        #expect(variables == [
            CommandVariable(name: "service.name", defaultValue: "payments api"),
            CommandVariable(name: "environment-name", defaultValue: "")
        ])
    }

    @Test func usesLaterDefaultForRepeatedVariable() {
        let raw = "deploy {{service}} and verify {{service=payments}}"

        let variables = TextVariables.variables(in: raw)

        #expect(variables == [
            CommandVariable(name: "service", defaultValue: "payments")
        ])
    }

    @Test func createsSegmentsAroundVariable() {
        let segments = TextVariables.segments(
            of: "deploy {{service=payments}} now",
            values: ["service": "billing"]
        )

        #expect(segments == [
            TextVariables.Segment(text: "deploy ", variableName: nil),
            TextVariables.Segment(text: "billing", variableName: "service"),
            TextVariables.Segment(text: " now", variableName: nil)
        ])
    }

    @Test func createsSegmentsForAdjacentVariables() {
        let segments = TextVariables.segments(
            of: "{{first=one}}{{second=two}}",
            values: [:]
        )

        #expect(segments == [
            TextVariables.Segment(text: "one", variableName: "first"),
            TextVariables.Segment(text: "two", variableName: "second")
        ])
    }

    @Test func createsSegmentsForTextStartingWithVariable() {
        let segments = TextVariables.segments(
            of: "{{service=payments}} now",
            values: [:]
        )

        #expect(segments == [
            TextVariables.Segment(text: "payments", variableName: "service"),
            TextVariables.Segment(text: " now", variableName: nil)
        ])
    }

    @Test func createsSegmentsForTextEndingWithVariable() {
        let segments = TextVariables.segments(
            of: "deploy {{service=payments}}",
            values: [:]
        )

        #expect(segments == [
            TextVariables.Segment(text: "deploy ", variableName: nil),
            TextVariables.Segment(text: "payments", variableName: "service")
        ])
    }

    @Test func createsSegmentForVariableOnlyText() {
        let segments = TextVariables.segments(
            of: "{{service=payments}}",
            values: [:]
        )

        #expect(segments == [
            TextVariables.Segment(text: "payments", variableName: "service")
        ])
    }

    @Test func createsSegmentForTextWithoutVariables() {
        let segments = TextVariables.segments(
            of: "deploy now",
            values: [:]
        )

        #expect(segments == [
            TextVariables.Segment(text: "deploy now", variableName: nil)
        ])
    }
}
