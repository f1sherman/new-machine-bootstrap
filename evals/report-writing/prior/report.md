For every PR containing or relying on evals, attach a readable case-by-case
report and link it from the description. Start with the question, tested scope,
coverage gaps and findings. Define shared base cases and settings once. Give
each variant a stable ID and an exact change from its named base; verify that
applying the changes reconstructs every frozen input. Identify policy, model,
effort, tools and limits separately from task changes.

Show compact results for every condition and repetition, including baselines,
ablations, controls, calibrations, failures and incomplete attempts. Reference
actual outputs and original per-criterion scores and reasons by stable IDs in
a readable evidence appendix; store identical material once. Keep controller
source and raw audit data out of the main reading path. Preserve superseded
scores. Name unavailable evidence and redactions; exclude secrets and provider
reasoning. A summary or raw JSON alone is not the report. Verify the uploaded
report's readable delivery, not only its checksum; HTML served as source text
is not a rendered report.
