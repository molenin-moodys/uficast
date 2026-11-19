import Foundation
import Testing
import UficastCore

private func segment(_ text: String, _ style: Int? = nil) -> StyledSegment { StyledSegment(text: text, style: style) }

@Test func plainSegmentsStayUnescaped() {
    let encoded = SpanMarkup.encode([segment("a < b & c")])
    #expect(encoded.text == "a < b & c")
    #expect(!encoded.hasMarkers)
    #expect(SpanMarkup.decode("x < y", styleCount: 0) == [segment("x < y")])
}

@Test func encodeWrapsAndEscapes() {
    let encoded = SpanMarkup.encode([segment("Use "), segment("bold", 0), segment(" & "), segment("<link>", 1)])
    #expect(encoded.text == "Use <s1>bold</s1> &amp; <s2>&lt;link&gt;</s2>")
    #expect(encoded.hasMarkers)
}

@Test func roundTripRestoresStyles() {
    let segments = [segment("Use "), segment("bold", 0), segment(" & "), segment("<link>", 1)]
    #expect(SpanMarkup.decode(SpanMarkup.encode(segments).text, styleCount: 2) == segments)
}

@Test func movedMarkersAreAccepted() {
    #expect(SpanMarkup.decode("<s1>Please</s1> check <s2>it</s2>", styleCount: 2)
            == [segment("Please", 0), segment(" check "), segment("it", 1)])
}

@Test func brokenMarkersFallBack() {
    for broken in ["<s3>x</s3>", "<s1><s2>x</s2></s1>", "<s1>x", "x</s1>", "<b>x</b>"] {
        #expect(SpanMarkup.decode(broken, styleCount: 2) == nil, "\(broken) must be rejected")
    }
}

@Test func entitiesAndStrayAmpersand() {
    #expect(SpanMarkup.decode("A &amp; B &lt;3 & co", styleCount: 1) == [segment("A & B <3 & co")])
}
