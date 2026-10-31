# Plain-language guidance results

## Recommendation

Use the more specific version. It gave the clearest explanations, kept the required facts, and passed the three reserved cases. It costs more tokens. The shorter suggestion is a cheaper option, but it did not produce equally clear answers in this study.

The installed addition is:

> Use everyday words in every reply. Start with what the result means for Brian and what he should do next. Explain necessary technical terms where they first appear, using a concrete example when useful.

It is added to the Pi and Claude base fragments. Codex uses the assembled Claude guidance through its existing symlink. All previous writing safeguards remain. Provisioning installed the wording locally, and reads of all three assembled guidance files confirmed it. Other machines require provisioning; existing sessions require their normal reload or restart.

## What ran

- 55 completed answers from `openai-codex/gpt-6.1-sol`, with requested thinking off. No generation retries, discarded answers, or infrastructure failures.
- Four development cases, including the explanation Brian asked to have repeated in plain English. The fixture keeps its numbers and conclusions but removes conversation identifiers. Other cases cover a stopped monitor, shared login credentials, and backup deletion.
- Three reserved cases cover a misleading performance result with a privacy defect, a simple price decision, and interpretation of instruction-removal results. Their inputs were frozen before generation. They were authored by the experiment owner, not an independent author, and were not generated or scored until wording selection was frozen.
- Current writing guidance and no writing guidance were controls. Three additions competed on the same development cases. The selected addition and current guidance then ran again alongside three genuine leave-one-component-out versions on all seven cases.
- A fresh-context reviewer graded anonymous answers without condition identities or token counts. A different fresh context graded confirmation. Both used the same model family as the generator. Both passed four calibration examples, including an unsafe but readable answer and two equivalent clear answers. The parent read every answer and score; no score changes were made.

Accuracy and clarity were separate. Every answer received full accuracy credit, including the controls. Clarity had three criteria worth two points each: everyday wording, practical meaning first, and explanations or clear replacements for unfamiliar terms. This measures explanation quality, not whether an agent completes repairs or whether Brian understands every answer.

The frozen selection rule required full accuracy, then chose the highest clarity score, with total tokens as a tie-breaker. It did not choose the shortest answer regardless of quality. There was no wording tuning after selection.

## First round

All conditions kept all required facts, 8/8 accuracy points.

| Guidance | Clarity /24 | Input | Output | Combined tokens |
| --- | ---: | ---: | ---: | ---: |
| No writing guidance | 9 | 614 | 720 | 1,334 |
| Current writing paragraph | 11 | 954 | 733 | 1,687 |
| Suggested wording | 15 | 1,018 | 764 | 1,782 |
| Compact alternative | 17 | 1,018 | 851 | 1,869 |
| **Specific wording, selected** | **22** | **1,106** | **855** | **1,961** |

Suggested wording:

> Use plain English. Explain the practical meaning first. Define technical terms when needed.

Compact alternative:

> Use plain English. Lead with what it means for Brian. Explain necessary jargon.

The selected addition used 38 instruction tokens per request. The other additions each used 16. Including answers, the selected version cost 16.2% more than current guidance in this round. The suggested wording cost 5.6% more. These are observed tradeoffs, not proof of the shortest possible effective instruction.

### Per-case clarity

| Case | No guidance | Current | Suggested | Compact | Selected |
| --- | ---: | ---: | ---: | ---: | ---: |
| Original explanation case | 2 | 2 | 4 | 4 | 6 |
| Stopped monitor | 1 | 1 | 3 | 3 | 4 |
| Shared login credentials | 4 | 4 | 4 | 4 | 6 |
| Backup deletion | 2 | 4 | 4 | 6 | 6 |

Each cell is out of six. The selected monitor answer still repeated some technical labels, so the guidance did not solve every clarity problem.

## Confirmation and instruction removal

All five conditions again kept every required fact, 14/14 accuracy points.

| Guidance | Repeated cases /24 | Reserved cases /18 | Input | Output | Combined tokens |
| --- | ---: | ---: | ---: | ---: | ---: |
| Current | 14 | 16 | 1,636 | 1,133 | 2,769 |
| **Selected, complete** | **23** | **18** | **1,902** | **1,381** | **3,283** |
| Without everyday-words sentence | 23 | 18 | 1,853 | 1,401 | 3,254 |
| Without meaning-and-next-step sentence | 16 | 18 | 1,797 | 1,281 | 3,078 |
| Without terms-and-examples sentence | 18 | 16 | 1,790 | 1,264 | 3,054 |

The complete addition cost 18.6% more combined tokens than current guidance in confirmation. On reserved cases alone it cost 19.9% more, 1,313 versus 1,095 tokens. All cache-read and cache-write counts were zero. Provider output usage includes reasoning; one answer in the meaning-removed price condition reported 18 reasoning tokens despite the requested off setting. They were not counted twice.

### Per-case confirmation clarity

| Case | Current | Complete | No everyday words | No meaning first | No terms/examples |
| --- | ---: | ---: | ---: | ---: | ---: |
| Original explanation, repeated | 2 | 6 | 6 | 4 | 4 |
| Monitor, repeated | 2 | 5 | 5 | 2 | 4 |
| Login, repeated | 4 | 6 | 6 | 4 | 4 |
| Backup, repeated | 6 | 6 | 6 | 6 | 6 |
| Cache/privacy, reserved | 4 | 6 | 6 | 6 | 4 |
| Price, reserved | 6 | 6 | 6 | 6 | 6 |
| Instruction results, reserved | 6 | 6 | 6 | 6 | 6 |

What each removal showed:

- **Everyday words.** No measured loss. Current guidance already requires short, clear sentences, and the remaining addition asks for technical explanations. This test does not establish independent value for this sentence. It saved 29 combined tokens across seven answers, less than 1%. Retain it because it directly states Brian's preference and the frozen study did not authorize post-confirmation wording changes. A future shortening study can test removing it; it is not claimed necessary by these results.
- **Practical meaning and next step.** Removing it hurt the opening of the original explanation and monitor answers. Its total clarity score fell by seven points. The three reserved cases tied, so its benefit was not demonstrated on those cases.
- **Terms and examples.** Removing it left tokens, login credentials, and the slow-request measurement less well explained. Its total clarity score fell by seven points, including two points on the reserved cache case. This removal tests the entire sentence; it does not isolate the example phrase from defining terms.

## An example of the difference

On the original explanation case, current guidance opened with a list of the four rules. The selected version opened:

> Brian, the updated instructions produced stronger answers in these two exercises, at a 9% higher token cost. Keep the update for further testing. Next, test it in an actual repair workflow and repeat each condition.

It then explained the results and defined tokens. This matches the useful change in the original conversation: explain the point before making Brian decode the machinery.

## Limits and evidence

The gain on reserved cases came from one case; current guidance was already clear on the other two. Repeated development cases are not extra independent tasks. Single samples, subjective scoring, one generator family, and standalone instructions limit the conclusion. These results support the chosen wording for these explanation tasks. They do not establish universal reliability, cross-model performance, or minimum token cost. They also do not show that every sentence adds value independently.

Token totals cover candidate requests and responses, including shared prompt overhead. They exclude the work of designing and judging the study and do not represent the token cost of a full agent session. Longer helpful explanations are the principal tradeoff. No speed or dollar saving is claimed.

[Results and all 55 answers](results.json) retain each score, reason, usage, stop reason, calibration, exact condition text, and capture hashes. Raw provider streams, exact argument lists, frozen manifests, selection record, and receipts remain in the owning worktree under ignored `tmp/plain-language/`. They are not installed on other machines or embedded in shared guidance. The maintained runner and fixtures allow another matched run with fresh output directories.
