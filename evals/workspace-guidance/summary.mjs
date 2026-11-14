import assert from 'node:assert/strict';

const fields=['input','output','cacheRead','cacheWrite'];
function usage(record){
  if(!Array.isArray(record.responses)||record.responses.length===0)return null;
  const total=Object.fromEntries(fields.map(field=>[field,0]));
  for(const response of record.responses){
    for(const field of fields){
      const value=response.usage?.[field];
      if(!Number.isFinite(value)||value<0)return null;
      total[field]+=value;
    }
  }
  return total;
}

export function summarizeComparison(rows,records){
  const pairs=[];
  for(const baseline of rows.filter(row=>row.condition==='guided')){
    const matches=rows.filter(row=>row.condition==='without_fragment'&&row.case===baseline.case&&row.repeat===baseline.repeat);
    assert.equal(matches.length,1,'Expected one matching fragment-removal trial');
    const controls=rows.filter(row=>row.condition==='empty_policy'&&row.case===baseline.case&&row.repeat===baseline.repeat);
    assert.equal(controls.length,1,'Expected one matching empty-policy trial');
    const alternative=matches[0], control=controls[0], original=records[baseline.file], removed=records[alternative.file], empty=records[control.file];
    const sameState=other=>Boolean(original?.before&&other?.before&&JSON.stringify(original.before)===JSON.stringify(other.before));
    const initialStateMatches=sameState(removed),controlInitialStateMatches=sameState(empty);
    const pass=row=>row.assessment.status==='complete'&&row.assessment.pass===true;
    const baselineUsage=usage(original||{}),removedUsage=usage(removed||{}),controlUsage=usage(empty||{});
    pairs.push({case:baseline.case,repeat:baseline.repeat,initialStateMatches,controlInitialStateMatches,baseline:baseline.assessment,withoutFragment:alternative.assessment,emptyPolicy:control.assessment,
      ...(initialStateMatches&&pass(baseline)&&pass(alternative)&&baselineUsage&&removedUsage?{candidateUsage:{baseline:baselineUsage,withoutFragment:removedUsage}}:{}),
      ...(controlInitialStateMatches&&pass(baseline)&&pass(control)&&baselineUsage&&controlUsage?{controlUsage:{baseline:baselineUsage,emptyPolicy:controlUsage}}:{})});
  }
  return {pairs,tokenRule:'Candidate tokens are reported only for matched pairs where both trials passed and usage is complete. Judge usage is excluded.'};
}
