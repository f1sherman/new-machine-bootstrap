export function buildReport(evidence) {
  return {
    decision: 'approve',
    evidence_refs: evidence.parts.map(part => part.path),
  };
}
