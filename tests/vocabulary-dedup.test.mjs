import assert from 'node:assert/strict';
import {test} from 'node:test';
import {deduplicateVocabulary} from '../app/vocabulary-dedup.ts';
test('first meaning and example survive case/space duplicates; input remains intact',()=>{
 const words=[{id:1,word:' Underground ',meaning:'지하의',example:'original'}, {id:2,word:'underground',meaning:'지하',example:'other'}, {id:3,word:'natural   record'}, {id:4,word:'Natural record'}, {id:5,word:'fossil'}];
 const {unique,excluded}=deduplicateVocabulary(words);
 assert.deepEqual(unique.map(x=>x.id),[1,3,5]);assert.deepEqual(excluded.map(x=>x.id),[2,4]);assert.equal(unique[0].meaning,'지하의');assert.equal(unique[0].example,'original');assert.equal(words.length,5);
});
test('DB-first mixed input deduplicates across sources, but different English sharing a meaning survives',()=>{
 const result=deduplicateVocabulary([{id:1,word:'capture',meaning:'잡다'},{id:-1,word:'Capture',meaning:'포획하다'},{id:-2,word:'catch',meaning:'잡다'}]);assert.deepEqual(result.unique.map(x=>x.id),[1,-2]);
});
test('163 input entries with four repeats leave 159 candidates for a 100 question test',()=>{
 const words=Array.from({length:159},(_,id)=>({id,word:'word'+id}));const result=deduplicateVocabulary([...words,...words.slice(0,4)]);assert.equal(result.unique.length,159);assert.equal(result.excluded.length,4);
});
