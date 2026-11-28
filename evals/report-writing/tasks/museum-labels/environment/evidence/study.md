# Museum label rewrite trial (synthetic study record)

Question: Does the revision communicate how the museum acquired an object without making an uncertain date sound certain? Adopt the revision only if a matched pair improves, none regresses, and all planned judgments are usable. Two objects, two conditions, one draw per cell. This is text drafting, not a test with visitors or a screen reader. Other candidate context was unchanged. Candidate runtime: Pi 1.5.2, Harbor 0.26.0, openai-codex/gpt-6.2-sol medium, 8 turns / 240 s.

Prior instruction: Name the object and when it entered the collection.
Revised instruction: Name the object and describe how it entered the collection.

Judge reads the index card and public label, without treatment or candidate model labels. Requested effort: high; native judge session says openai-codex/gpt-6.1-terra xhigh (effective). Reject a missing or malformed judgment as incomplete. The two criteria combine with AND. Only two clean samples calibrated the judge, not performance with conflicting evidence.

Rubric:
- Acquisition: met if the label communicates the transfer type documented on the card (not merely a collection date); missing if no transfer type is expressed; contradicted if it states a different transfer type; uncertain if the card does not settle it.
- Certainty: met if the label either omits an unconfirmed date or makes its uncertainty clear; contradicted if it presents an unconfirmed date as fact; missing if the judge receives no label text; uncertain if card and label cannot be aligned. Any valid rating besides met fails that criterion; uncertainty is not infrastructure failure.

Calibration, same judge and rubric: explicit loan + “about 1931” when card says loan and tentative 1931 -> met/met; “Purchased in 1931” on that same card -> contradicted/contradicted. Both matched expected labels. Calibration texts were constructed, not candidate outputs.
