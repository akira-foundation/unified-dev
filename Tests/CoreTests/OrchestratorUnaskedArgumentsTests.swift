import Testing
@testable import Core

@Suite("Listed programs whose arguments make them write or run another")
struct OrchestratorUnaskedArgumentsTests {
    @Test("a listed program told to write a file is refused", arguments: [
        "uniq in out", "uniq -c in out", "uniq -f 2 in out", "uniq --skip-fields 2 in out", "uniq - out",
        "uniq -- in out", "tree -o out", "tree -aR -H . -L 1", "tree --output=out", "file -C -m magic",
        "file --compile -m magic",
    ])
    func writes(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .refused)
    }

    @Test("the same programs reading pass", arguments: [
        "uniq in", "uniq -c in", "uniq -f 2 in", "uniq --skip-fields 2 in", "uniq -s1 in", "uniq",
        "tree -L 2", "tree -a src", "file x", "file -b x", "sort -n file", "rg -n x src",
    ])
    func reads(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .passes)
    }

    @Test("a listed program told to run another asks", arguments: [
        "sort --compress-program=gzip file", "sort --compress-program gzip file", "rg --pre ./x pattern",
        "rg --pre=x pattern", "rg --hostname-bin=x pattern",
    ])
    func runsAnother(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .asks)
    }

    @Test("xargs asks when what it reads could make its program write or run", arguments: [
        "xargs sort", "xargs uniq", "xargs tree", "xargs rg x", "xargs tar -t", "xargs file", "xargs date",
        "xargs hostname", "xargs git log", "xargs gh pr view", "xargs find", "xargs sed -n p", "xargs -n 1 sort",
        "xargs -I {} cat {}", "xargs env cat",
    ])
    func xargsAsks(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .asks)
    }

    @Test("xargs passes in front of a program its arguments cannot steer", arguments: [
        "xargs", "xargs cat", "xargs -n 1 grep x", "xargs -0 wc -l", "xargs /bin/ls -l",
    ])
    func xargsPasses(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .passes)
    }
}
