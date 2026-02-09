# AGENTS

This file captures how to work with me (the user) and how to build specialized Codex agents that align with my workflow while staying professional.

## Working Agreement

### Goals
- Build software efficiently with high engineering rigor.
- Optimize for maintainability, correctness, and long-term velocity.

### Collaboration Style
- Preferred communication style: To the point, partner closely to avoid drifting from requirements.
- Level of detail in explanations: Concise, but include key decisions and rationale.
- How to surface tradeoffs/risks: Call out explicitly and ask for approval when it impacts scope or requires refactor.
- When to ask questions vs. make assumptions: Ask when requests conflict, requirements are unclear, or a refactor may be the best path.
- UI assistance: If Xcode/UI clicks are needed, ask the user to perform them; user will intervene to speed progress.
- Skill reminders: When a request would benefit from an available skill, explicitly remind the user and propose using it.
- Prompt coaching: Provide occasional, high-impact recommendations on how to prompt effectively for the task at hand.
 - Context loading: Always review project docs before planning or executing work (see “Required Context Docs”).

### Technical Preferences
- Primary languages/frameworks: Modern native iOS development (Swift, Xcode toolchain).
- Architecture style (monolith/services/modular): TBD per feature; ask if architectural refactor is implied.
- Code style and linting rules: Use native iOS/Xcode defaults unless directed.
- Testing philosophy (unit/integration/e2e): 100% unit test coverage. TDD required.
- Documentation expectations (docstrings/ADRs/README): Feature design documents with pseudocode for implementation handoff.

### Quality Bar
- Definition of Done (DoD): Tests required. Feature meets user-approved requirements in full.
- Review expectations (self-review, checklists): Explicitly confirm requirements coverage and test completeness.
- Performance/observability expectations: Ask if performance or telemetry requirements apply.
- Security/privacy constraints: None specified; treat as personal app unless told otherwise.
- Merge discipline: Work in small, reviewable PR-sized batches and pause for user approval before proceeding.
- Mainline health: `main` should remain buildable and usable at all times; keep changes incremental.
- Test execution: Prefer Codex running TDD tests (e.g., `xcodebuild test`) to verify compliance whenever possible.
- PR workflow: Create a branch from `main`, commit changes, push, open a GitHub PR, and wait for approval before continuing.
- PR formatting: Ensure PR bodies use proper newlines (not literal `\\n`) and include Summary + Testing sections.
 - Project plan maintenance: Keep `docs/project-plan.md` updated with progress whenever work completes a phase item.

### Tooling
- Package managers/build tools: Native iOS default tools only. Third-party dependencies require explicit approval.
- CI/CD expectations: Not specified; ask if needed.
- Local dev workflow: Xcode-first.
- Preferred commands for search, tests, lint, format: Use default Xcode tooling.

### Constraints
- Non-negotiables (licensing, dependencies, runtime, infra): Avoid third-party deps unless (a) standard, (b) well supported, and (c) user approves.
- Time/cost constraints: None specified.
- Any platforms/OS targets: iOS (modern native).

## Specialized Agents

### What an agent should include
- A narrow scope (single domain or workflow)
- A repeatable workflow with guardrails
- References to key files or scripts in this repo

### Candidate agents (initial)
- Product Owner / Feature Designer
  - Scope: Research current patterns in repo, propose options, decide with user, and produce a feature design doc with pseudocode.
  - Trigger: "Think with me about feature X" or any request to propose/decide approaches.
  - Inputs needed: Feature requirements, relevant files, constraints.
  - Outputs: Feature design document + pseudocode + open questions.
- Feature Implementation
  - Scope: Read feature design doc, ask clarifying questions, implement end-to-end, and add unit tests.
  - Trigger: "Implement this feature" with a design doc.
  - Inputs needed: Approved design doc + acceptance criteria.
  - Outputs: Code changes, tests, and a test strategy walkthrough.

## Next Steps for New Agents

1. Define the agent scope and when it should trigger.
2. List the key repo files, commands, and decision rules it should follow.
3. Draft a skill folder with `SKILL.md` and optional `references/` or `scripts/`.
4. Validate the workflow on a real task and refine.
5. For iOS modernization guidance, run targeted research and summarize current best practices for review.
6. Deliver work in PR-sized increments with explicit architecture notes and an approval checkpoint.

## Required Context Docs
Review these before planning or implementing work:
- `docs/project-plan.md`
- `docs/scope-and-non-goals.md`
- `docs/product-north-star.md`
- `docs/repo-inventory.md`
