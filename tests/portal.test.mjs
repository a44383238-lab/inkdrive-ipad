import test from 'node:test';import assert from 'node:assert/strict';
import {generateKeyPairSync,privateDecrypt,constants} from 'node:crypto';
import {portalEnvelope,portalTimetable} from '../shared/portal.mjs';
test('school request body uses fresh RSA PKCS1 chunks and retains the official nested JSON envelope',()=>{
  const {publicKey,privateKey}=generateKeyPairSync('rsa',{modulusLength:2048}),jwk=publicKey.export({format:'jwk'});
  const settings={modulus:Buffer.from(jwk.n,'base64url').toString('hex'),exponent:Buffer.from(jwk.e,'base64url').toString('hex'),auth:'session-menu-proof'};
  const query={SCH_SYEAR:'2027',SCH_TERM_GCD:'0010',label:'한글'.repeat(100)};
  const first=portalEnvelope(query,settings),second=portalEnvelope(query,settings);assert.notEqual(first._data,second._data);
  const decoded=first._data.split(',').map(hex=>{const block=privateDecrypt({key:privateKey,padding:constants.RSA_NO_PADDING},Buffer.from(hex,'hex'));assert.equal(block[1],2);return block.subarray(block.indexOf(0,2)+1).toString('utf8');}).join('');
  const wrapper=JSON.parse(decoded);assert.equal(wrapper.AUTH_STR,settings.auth);assert.deepEqual(JSON.parse(wrapper._data),{...query,locale:'0001'});
});
test('portal API refuses an unauthenticated page without issuing a timetable request',async()=>{
  let calls=0;await assert.rejects(portalTimetable({html:async()=>'<form>login</form>',request:async()=>{calls++;}},'2027-0010'),/로그인/);assert.equal(calls,0);
});
