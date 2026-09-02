---
description: Execute a goal with matched subagents and independent validation
argument-hint: "<goal>"
---
Execute this goal end-to-end: $@

Use available built-in subagents. Respect repository instructions and existing approval, commit, push, and publication boundaries.

1. Inspect enough context to define success and the smallest viable workflow. Select only roles that materially help: `scout` for local discovery, `researcher` for external facts, `oracle` to challenge human assumptions or risky decisions, `delegate` for bounded general work, `worker` for implementation, and fresh `reviewer` agents for verification.
2. Before implementation, use `oracle` only when material uncertainty or tradeoffs warrant challenging the goal or proposed direction. Revise from evidence, not preference. Ask me only when an unresolved decision requires human authority.
3. Follow `clarify → scout → worker → fresh reviewers → worker` where useful, skipping needless stages. Use a direct child call for one bounded task and one async `workflowScript` with stable keys for sequence or fanout. Keep parent as arbiter, parallelize only independent read-only work, and keep one writer per worktree.
4. Validate the resulting diff with fresh-context reviewers for correctness and tests, plus one reviewer using `ponytail-review` for unnecessary complexity. Synthesize findings before resuming the retained `worker`, or launching one replacement worker, to apply accepted fixes and run the smallest relevant checks. Repeat only while P0/P1 or clear behavior-preserving simplifications remain, maximum three review rounds.
5. Report outcome, changed files, checks, reviewer verdicts, unresolved risks, and anything requiring my approval. Never commit, push, open a PR, merge, or publish unless the goal explicitly authorizes it.
