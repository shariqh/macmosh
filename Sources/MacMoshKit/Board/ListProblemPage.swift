import Foundation

/// The page for a saved list that can't be read (look design 6.7): a heading, the menu's sentence
/// (`BoardOnScreen.listProblem`), then what happens next. No pill, since it shows no workhorse.
public struct ListProblemPage: Sendable, Equatable {
    public var heading: String
    /// The store's sentence, as the menu shows it: "Can't read MacMosh's saved settings: …".
    public var problem: String
    public var nextStep: String

    public init(heading: String, problem: String, nextStep: String) {
        self.heading = heading
        self.problem = problem
        self.nextStep = nextStep
    }

    /// The two fixed parts around the menu's sentence.
    public init(problem: String) {
        self.init(heading: Self.headingWords, problem: problem, nextStep: Self.nextStepWords)
    }

    /// Proposed in look step 2; the owner approves them in the pull request. The alternative: "Your saved Macs can't
    /// be read".
    public static let headingWords = "MacMosh can't list your Macs"
    /// Proposed in look step 2; the owner approves them in the pull request. True because the board reads the list
    /// again whenever a check starts and clears the problem when it reads (`BoardOnScreen`). The alternative: "Fix the
    /// file, or update MacMosh if the line above says so. MacMosh reads it again at each check."
    public static let nextStepWords = "Once the file can be read again, your Macs come back at the next check."
}
