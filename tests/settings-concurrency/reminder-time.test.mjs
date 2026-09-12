import test from 'node:test';
import assert from 'node:assert/strict';
import {koreanDay,untilNextKoreanDay} from '../../app/schedule-reminder-time.ts';
import {calendarValues,settingsChanges} from '../../app/settings-concurrency.ts';
test('Korean day switches at UTC 15:00, not UTC midnight',()=>{
 assert.equal(koreanDay(new Date('2026-09-12T14:59:59Z')),'2026-09-12');
 assert.equal(koreanDay(new Date('2026-09-12T15:00:00Z')),'2026-09-13');
});
test('one midnight timer has a bounded positive delay across month/year changes',()=>{
 for(const instant of ['2026-12-31T14:59:59Z','2026-12-31T15:00:00Z','2026-09-12T00:00:00Z']){
  const now=new Date(instant),delay=untilNextKoreanDay(now);
  assert.ok(delay>0&&delay<=86400250);
  assert.notEqual(koreanDay(new Date(now.getTime()+delay)),koreanDay(now));
 }
});
test('reminder preference is an independent calendar conflict field',()=>{
 const event={scope:'academy',category:'consultation',startsOn:'2026-09-12',endsOn:'2026-09-12',startsAt:null,endsAt:null,school:null,grade:null,title:'Test',classId:null,teacherId:'teacher',note:null,contactName:null,contactPhone:null,location:null,status:'scheduled'};
 assert.deepEqual(settingsChanges(calendarValues(event),calendarValues({...event,reminderEnabled:true})),{reminderEnabled:true});
});
