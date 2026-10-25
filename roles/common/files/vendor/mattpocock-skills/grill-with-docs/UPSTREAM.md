# Upstream provenance

- Repository: https://github.com/mattpocock/skills.git
- Tag: `v1.3.1`
- Commit: `24fe0ef7737efae15c87225755e9f6f5965e4888`
- Local patches:
  - Require explicit invocation in SKILL.md and agents/openai.yaml.
  - Load grilling and domain-modeling through the harness skill mechanism, with sibling SKILL.md files as the fallback when the mechanism is unavailable or cannot load either dependency (including invocation-policy rejection).
