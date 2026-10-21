import {createPublicKey,publicEncrypt,constants} from 'node:crypto';
export function portalEnvelope(query,{modulus,exponent,auth=null,locale='0001'}) {
  if(!/^[0-9a-f]+$/i.test(modulus)||modulus.length<256||modulus.length>2048||!/^[0-9a-f]+$/i.test(exponent))throw new Error('학교 공개키를 확인해 주세요.');
  const toBytes=hex=>Buffer.from(hex.length%2?'0'+hex:hex,'hex');
  const key=createPublicKey({format:'jwk',key:{kty:'RSA',n:toBytes(modulus).toString('base64url'),e:toBytes(exponent).toString('base64url')}});
  const wrapper={_data:JSON.stringify({...query,locale})};if(auth!=null)wrapper.AUTH_STR=auth;
  const plain=JSON.stringify(wrapper),chunks=[];let current='';
  for(const character of plain){if(Buffer.byteLength(current+character)>200){chunks.push(current);current='';}current+=character;}if(current)chunks.push(current);
  return {_data:chunks.map(chunk=>publicEncrypt({key,padding:constants.RSA_PKCS1_PADDING},Buffer.from(chunk)).toString('hex')).join(',')};
}
export async function portalTimetable(client,term) {
  const page=await client.html('https://onestop.pusan.ac.kr/main');
  const modulus=/RSAModulus\s*=\s*['"]([0-9a-f]+)['"]/i.exec(page)?.[1],exponent=/RSAExponent\s*=\s*['"]([0-9a-f]+)['"]/i.exec(page)?.[1],csrf=/scwin\.token\s*=\s*['"]([^'"]+)['"]/.exec(page)?.[1];
  if(!modulus||!exponent||!csrf)throw new Error('학지시 로그인을 확인해 주세요.');
  const post=async(path,query,auth=null)=>{
    const response=await client.request('https://onestop.pusan.ac.kr'+path,{method:'POST',headers:{'Content-Type':'application/json','X-CSRF-TOKEN':csrf,AJAX:'true'},body:JSON.stringify(portalEnvelope(query,{modulus,exponent,auth}))});
    const value=await response.json();if(String(value.statusCode)==='440')throw new Error('학지시 로그인이 만료됐어요.');return value;
  };
  const info=await post('/global/info',{menuCD:'000000000000000'});if(!info._LoginUser)throw new Error('학지시 로그인을 확인해 주세요.');
  const menu=info._Menu?.find(item=>Object.values(item).some(v=>String(v).includes('persontimetablesearch')));
  const year=term.slice(0,4),semester=term.slice(-4);
  const result=await post('/ost/cls/timetablesearch/persontimetablesearch/selectPersonTimetable',{SCH_SYEAR:year,SCH_TERM_GCD:semester,SYEAR:year,TERM_GCD:semester},menu?.AUTH_STR);
  if(!Array.isArray(result.data))throw new Error('시간표 응답을 확인해 주세요.');return result.data;
}
