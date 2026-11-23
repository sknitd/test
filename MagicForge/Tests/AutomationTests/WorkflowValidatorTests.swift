import XCTest
import MFCore
@testable import MFAutomation

final class WorkflowValidatorTests: XCTestCase {
    private func issues(_ steps: [WorkflowStep], timeout: Double = 30, configuration: Configuration = Configuration()) -> [String] {
        WorkflowValidator.issues(for: Workflow(name: "W", steps: steps, timeout: timeout), in: configuration)
    }

    func testValidWorkflowHasNoIssues() {
        var configuration = Configuration()
        let menu = RadialMenu(name: "M")
        let template = PromptTemplate(name: "P")
        configuration.radialMenus = [menu]
        configuration.ai.templates = [template]
        let steps: [WorkflowStep] = [
            .action(.a), .action(.none), .delay(seconds: 0.5), .delay(seconds: 60),
            .waitForApp(bundleID: "com.apple.Safari", timeout: 10), .notify(title: "Hi", body: ""),
            .action(.radialMenu(id: menu.id)), .action(.ai(templateID: template.id)), .action(.control(.nextProfile)),
            .conditional(.not(.clipboardContains("x")), then: [.action(.b)], otherwise: []),
        ]
        XCTAssertEqual(issues(steps, configuration: configuration), [])
    }

    func testEmptyWorkflow() {
        XCTAssertEqual(issues([]), ["The workflow has no steps."])
    }

    func testNestedWorkflowsAreForbiddenAtAnyDepth() {
        let nested = WorkflowStep.action(.workflow(id: UUID()))
        XCTAssertEqual(issues([nested]), ["Step 1 runs another workflow. Workflows cannot be nested."])
        let deep = issues([.action(.a), .conditional(.appIsRunning(bundleID: "x"), then: [.action(.a)],
                                                     otherwise: [.action(.b), nested])])
        XCTAssertEqual(deep, ["Step 2 › Otherwise 2 runs another workflow. Workflows cannot be nested."])
        XCTAssertTrue(WorkflowValidator.containsNestedWorkflow([.conditional(.appIsRunning(bundleID: "x"), then: [nested],
                                                                             otherwise: [])]))
        XCTAssertFalse(WorkflowValidator.containsNestedWorkflow([.action(.a)]))
    }

    func testUnknownReferences() {
        let found = issues([.action(.radialMenu(id: UUID())),
                            .conditional(.appIsRunning(bundleID: "x"), then: [.action(.ai(templateID: UUID()))], otherwise: [])])
        XCTAssertEqual(found, ["Step 1 opens a radial menu that no longer exists.",
                               "Step 2 › Then 1 uses an AI prompt that no longer exists."])
    }

    func testDelays() {
        XCTAssertEqual(issues([.delay(seconds: 0)]).count, 1)
        XCTAssertEqual(issues([.delay(seconds: -1)]).count, 1)
        XCTAssertEqual(issues([.delay(seconds: .nan)]).count, 1)
        XCTAssertEqual(issues([.delay(seconds: .infinity)]).count, 1)
        XCTAssertEqual(issues([.delay(seconds: 60.5)]),
                       ["Step 1 waits 60.5 seconds; a single delay is limited to 60 seconds."])
        XCTAssertEqual(issues([.delay(seconds: 60)]), [])
    }

    func testWaitForApp() {
        XCTAssertEqual(issues([.waitForApp(bundleID: " ", timeout: 5)]), ["Step 1 waits for an app but no app is chosen."])
        XCTAssertEqual(issues([.waitForApp(bundleID: "a.b", timeout: 0)]).count, 1)
        XCTAssertEqual(issues([.waitForApp(bundleID: "a.b", timeout: .nan)]).count, 1)
        XCTAssertEqual(issues([.waitForApp(bundleID: "a.b", timeout: 121)]).count, 1)
        XCTAssertEqual(issues([.waitForApp(bundleID: "a.b", timeout: 120)]), [])
    }

    func testTimeoutRange() {
        XCTAssertEqual(issues([.action(.a)], timeout: 0.5).count, 1)
        XCTAssertEqual(issues([.action(.a)], timeout: 601).count, 1)
        XCTAssertEqual(issues([.action(.a)], timeout: .nan).count, 1)
        XCTAssertEqual(issues([.action(.a)], timeout: 1), [])
        XCTAssertEqual(issues([.action(.a)], timeout: 600), [])
    }

    func testStepCountCap() {
        XCTAssertEqual(issues(Array(repeating: .action(.a), count: 200)), [])
        XCTAssertEqual(issues(Array(repeating: .action(.a), count: 201)), ["The workflow has 201 steps; the limit is 200."])
        let branch = Array(repeating: WorkflowStep.action(.a), count: 100)
        let conditional = WorkflowStep.conditional(.appIsRunning(bundleID: "x"), then: branch, otherwise: branch)
        XCTAssertEqual(WorkflowValidator.stepCount([conditional]), 201)
        XCTAssertEqual(issues([conditional]).count, 1)
    }

    func testConditionalDepth() {
        func nest(_ depth: Int) -> WorkflowStep {
            depth == 0 ? .action(.a) : .conditional(.appIsRunning(bundleID: "x"), then: [nest(depth - 1)], otherwise: [])
        }
        XCTAssertEqual(issues([nest(4)]), [])
        let tooDeep = issues([nest(5)])
        XCTAssertEqual(tooDeep.count, 1)
        XCTAssertTrue(tooDeep[0].contains("more than 4 levels"))
        // Very deep input still terminates with one issue.
        XCTAssertEqual(issues([nest(40)]).count, 1)
    }

    func testConditions() {
        XCTAssertEqual(issues([.conditional(.frontmostAppIs(bundleID: ""), then: [.action(.a)], otherwise: [])]).count, 1)
        XCTAssertEqual(issues([.conditional(.not(.clipboardContains("")), then: [.action(.a)], otherwise: [])]).count, 1)
        XCTAssertEqual(issues([.conditional(.appIsRunning(bundleID: "x"), then: [], otherwise: [])]).count, 1)
        XCTAssertEqual(issues([.notify(title: " ", body: "")]).count, 1)
    }

    func testScriptsAreCollected() {
        let one = ScriptAction.shell(command: "ls")
        let two = ScriptAction.shortcut(name: "Focus")
        let flow = Workflow(name: "W", steps: [.action(.script(one)), .conditional(.appIsRunning(bundleID: "x"), then: [],
                                                                                   otherwise: [.action(.script(two))])])
        XCTAssertEqual(WorkflowValidator.scripts(in: flow), [one, two])
    }
}
