---
name: humanizer
description: >
  Use when given text to remove AI writing patterns and make writing sound more
  natural and human. Apply when reviewing or editing prose, documentation, blog
  posts, or any written content that may contain AI-generated artifacts.
---

# Humanizer: Remove AI Writing Patterns

Strip AI tells. Make the text sound natural, human, and specific. Based on Wikipedia's "Signs of AI writing" page, maintained by WikiProject AI Cleanup.

## Task

When given text to humanize:

1. **Find AI patterns** - Scan for the patterns below.
2. **Rewrite the weak parts** - Replace AI-isms with plain alternatives.
3. **Keep the meaning** - Preserve the core message.
4. **Match the voice** - Stay formal, casual, technical, or whatever the text needs.
5. **Keep source voice and neutrality** - Preserve neutral, factual, technical, or house-style-constrained text as neutral.
6. **Add soul when it fits** - Remove slop, but do not inject opinions, feelings, first-person voice, tangents, or personality into text that should stay neutral.
7. **Keep structure intact** - Preserve code spans, commands, links, headings, markup, and other formatting that should remain unchanged.

## Personality and Soul

Cutting AI patterns is not enough. Clean but lifeless writing still reads fake. Good writing sounds like a person with an actual point of view.
Use this section only when the source and context support a more personal voice. Do not force it onto neutral, factual, or technical text.

### Signs of soulless writing (even if technically "clean"):
- Every sentence has the same length and shape
- No opinions, just neutral reporting
- No uncertainty or mixed feelings
- No first-person voice when it fits
- No humor, edge, or personality
- Reads like a Wikipedia article or press release

### How to add voice:

**Have opinions.** Don't just report facts. React to them. "I genuinely don't know how to feel about this" sounds more human than a balanced list of pros and cons.

**Vary the rhythm.** Use short, sharp sentences. Then use longer ones that take their time. Don't keep the same cadence.

**Acknowledge complexity.** Real people are conflicted. "This is impressive but also kind of unsettling" beats "This is impressive."

**Use "I" when it fits.** First person is not unprofessional. It is direct.

**Leave some rough edges.** Perfect structure feels mechanical. Tangents, asides, and half-formed thoughts feel human.

**Name the feeling.** Not "this is concerning," but "there's something unsettling about agents churning away at 3am while nobody's watching."

**Stay within the source.** Do not invent specifics, facts, dates, causes, attributions, or sources. Use only details already in the input or separately verified.

## Content Patterns

### 1. Undue Emphasis on Significance, Legacy, and Broader Trends

**Words to watch:** stands/serves as, is a testament/reminder, a vital/significant/crucial/pivotal/key role/moment, underscores/highlights its importance, reflects broader, symbolizing its ongoing/enduring/lasting, setting the stage for, marking/shaping the, represents/marks a shift, key turning point, evolving landscape, indelible mark

**Problem:** AI inflates importance by turning ordinary facts into broad historical claims.

**Before:**
> The Statistical Institute of Catalonia was officially established in 1989, marking a pivotal moment in the evolution of regional statistics in Spain.

**After:**
> The Statistical Institute of Catalonia was established in 1989.

### 2. Undue Emphasis on Notability and Media Coverage

**Words to watch:** independent coverage, local/regional/national media outlets, active social media presence

**Problem:** AI overstates notability and lists outlets without context.

**Before:**
> Her views have been cited in The New York Times, BBC, Financial Times, and The Hindu. She maintains an active social media presence with over 500,000 followers.

**After:**
> Her views have been cited in The New York Times, the BBC, the Financial Times, and The Hindu. She also has more than 500,000 social media followers.

### 3. Superficial Analyses with -ing Endings

**Words to watch:** highlighting/underscoring/emphasizing..., ensuring..., reflecting/symbolizing..., contributing to..., cultivating/fostering..., showcasing...

**Problem:** AI pads sentences with present-participle phrases to sound deeper.

**Before:**
> The temple's color palette resonates with the region's natural beauty, symbolizing Texas bluebonnets, showcasing how these elements have integrated into the traditional aesthetic.

**After:**
> The temple's color palette reflects the region around it, including Texas bluebonnets.

### 4. Promotional and Advertisement-like Language

**Words to watch:** boasts a, vibrant, rich (figurative), profound, enhancing its, showcasing, exemplifies, commitment to, natural beauty, nestled, in the heart of, groundbreaking (figurative), renowned, breathtaking, must-visit, stunning

**Before:**
> Nestled within the breathtaking region of Gonder in Ethiopia, Alamata Raya Kobo stands as a vibrant town with a rich cultural heritage and stunning natural beauty.

**After:**
> Alamata Raya Kobo is a town in the Gonder region of Ethiopia.

### 5. Vague Attributions and Weasel Words

**Words to watch:** Industry reports, Observers have cited, Experts argue, Some critics argue, several sources/publications

**Before:**
> Experts believe it plays a crucial role in the regional ecosystem.

**After:**
> Some experts say it plays an important role in the regional ecosystem.

### 6. Outline-like "Challenges and Future Prospects" Sections

**Words to watch:** Despite its... faces several challenges..., Despite these challenges, Challenges and Legacy, Future Outlook

**Before:**
> Despite its industrial prosperity, Korattur faces challenges typical of urban areas, including traffic congestion and water scarcity. Despite these challenges, Korattur continues to thrive.

**After:**
> Korattur faces traffic congestion and water scarcity.

## Language and Grammar Patterns

### 7. Overused "AI Vocabulary" Words

**High-frequency AI words:** Additionally, align with, crucial, delve, emphasizing, enduring, enhance, fostering, garner, highlight (verb), interplay, intricate/intricacies, key (adjective), landscape (abstract noun), pivotal, showcase, tapestry (abstract noun), testament, underscore (verb), valuable, vibrant

### 8. Avoidance of "is"/"are" (Copula Avoidance)

**Words to watch:** serves as/stands as/marks/represents [a], boasts/features/offers [a]

**Before:**
> Gallery 825 serves as LAAA's exhibition space. The gallery features four separate spaces and boasts over 3,000 square feet.

**After:**
> Gallery 825 is LAAA's exhibition space. The gallery has four rooms totaling 3,000 square feet.

### 9. Negative Parallelisms

**Problem:** "Not only...but..." and "It's not just about..., it's..." show up too often.

### 10. Rule of Three Overuse

**Problem:** AI forces ideas into threes to sound complete.

**Before:**
> The event features keynote sessions, panel discussions, and networking opportunities. Attendees can expect innovation, inspiration, and industry insights.

**After:**
> The event includes talks and panels. There's also time for informal networking between sessions.

### 11. Elegant Variation (Synonym Cycling)

**Problem:** AI swaps in new words too often to avoid repetition.

**Before:**
> The protagonist faces many challenges. The main character must overcome obstacles. The central figure eventually triumphs. The hero returns home.

**After:**
> The protagonist faces many challenges but eventually triumphs and returns home.

### 12. False Ranges

**Problem:** AI uses "from X to Y" even when X and Y are not on the same scale.

## Style Patterns

These are heuristics, not automatic errors. Keep em dashes, boldface, title case, curly quotes, and similar formatting when they are intentional house style or required formatting.

### 13. Em Dash Overuse

**Problem:** AI uses em dashes more than people do, often to sound punchy.

### 14. Overuse of Boldface

**Problem:** AI bolds phrases mechanically.

### 15. Inline-Header Vertical Lists

**Problem:** AI writes lists where each item starts with a bold header and a colon. Prefer prose or simpler lists.

### 16. Title Case in Headings

**Problem:** AI capitalizes every main word in headings. Use sentence case.

### 17. Emojis

**Problem:** AI adds emojis to headings or bullets without being asked.

### 18. Curly Quotation Marks

**Problem:** ChatGPT often uses curly quotes instead of straight quotes.

## Communication Patterns

### 19. Collaborative Communication Artifacts

**Words to watch:** I hope this helps, Of course!, Certainly!, You're absolutely right!, Would you like..., let me know, here is a...

**Problem:** Chatbot copy leaks into the content.

### 20. Knowledge-Cutoff Disclaimers

**Words to watch:** as of [date], While specific details are limited/scarce..., based on available information...

### 21. Sycophantic/Servile Tone

**Problem:** Overly positive, people-pleasing language. "Great question!" is not content.

## Filler and Hedging

### 22. Filler Phrases

Common replacements:
- "In order to achieve this goal" -> "To achieve this"
- "Due to the fact that" -> "Because"
- "At this point in time" -> "Now"
- "In the event that" -> "If"
- "has the ability to" -> "can"
- "It is important to note that the data shows" -> "The data shows"

### 23. Excessive Hedging

**Before:**
> It could potentially possibly be argued that the policy might have some effect on outcomes.

**After:**
> The policy may affect outcomes.

### 24. Generic Positive Conclusions

**Problem:** Vague upbeat endings like "The future looks bright" or "Exciting times lie ahead."

**Fix:** End with a concrete fact or next step.

## Process

1. Read the input carefully.
2. Find the patterns that genuinely apply. Do not treat every heuristic as an automatic error.
3. Rewrite each weak section.
4. Keep the source voice, tone, and structure where they matter.
5. Do not invent facts, dates, causes, attributions, or sources.
6. Preserve technical markup and document structure.
7. Keep the result natural aloud.
8. Vary sentence structure.
9. Use specific details instead of vague claims.
10. Keep the tone appropriate to the context.
11. Use simple constructions like is/are/has when they fit.
12. Return the humanized version.

## Output Format

Provide:
1. The rewritten text
2. A brief summary of changes made, if helpful

## Reference

Based on [Wikipedia:Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing), maintained by WikiProject AI Cleanup.

Key insight: "LLMs use statistical algorithms to guess what should come next. The result tends toward the most statistically likely result that applies to the widest variety of cases."
