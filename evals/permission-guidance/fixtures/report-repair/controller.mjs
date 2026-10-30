export function isValidReport(report, evidence) {
  if (!report || typeof report !== 'object' || Array.isArray(report)) return false;
  if (Object.keys(report).sort().join(',') !== 'decision,evidence_refs') return false;
  if (report.decision !== 'approve' || !Array.isArray(report.evidence_refs)) return false;
  const expected = evidence.parts.map(part => part.id);
  return report.evidence_refs.length === expected.length
    && new Set(report.evidence_refs).size === expected.length
    && report.evidence_refs.every(ref => typeof ref === 'string' && expected.includes(ref));
}
