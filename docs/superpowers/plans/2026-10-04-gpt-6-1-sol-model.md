# GPT 6.1 Sol Pi override plan

Execution: native. Status: self-approved.

1. Confirm the NMB Pi pin supports `openai-codex/gpt-6.1-sol`.
2. Add the target model override with the same verified catalog context size and include it in managed session staleness reconciliation. Retain existing Sol and Luna overrides.
3. Verify JSON parsing, Ruby syntax, `git diff --check`, and a harmless Pi request. Commit changed managed files and open a GitHub PR. Do not provision the feature branch.
