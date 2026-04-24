@testable import dug
import Testing

struct EnhancedFormatterEDETests {
    @Test("Pseudosection shows EDE when present")
    func pseudosectionShowsEDE() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "blocked.example.com")
        let output = formatter.format(result: TestFixtures.withEDESystem, query: query, options: QueryOptions())
        #expect(output.contains(";; SYSTEM RESOLVER PSEUDOSECTION:"))
        #expect(output.contains(";; EDE: 18 (Prohibited)"))
    }

    @Test("Pseudosection shows EDE with extra text")
    func pseudosectionShowsEDEWithExtraText() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "blocked.example.com")
        let output = formatter.format(
            result: TestFixtures.withEDEExtraText,
            query: query,
            options: QueryOptions()
        )
        #expect(output.contains(";; EDE: 18 (Prohibited): \"blocked by policy\""))
    }

    @Test("No EDE line when metadata has no EDE")
    func noEDELineWhenAbsent() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(!output.contains("EDE:"))
    }
}
