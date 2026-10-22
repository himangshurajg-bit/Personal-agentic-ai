import asyncio
import json
import time
import pytest
from httpx import ASGITransport, AsyncClient
from app import create_app, Ollama
TOKEN='x'*32
class Recorder:
    def __init__(self, fail=False): self.messages=[]; self.fail=fail
    async def stream(self,messages):
        self.messages=messages
        yield 'hello '
        if self.fail: raise TimeoutError('weak connection')
        yield 'world'
@pytest.fixture
async def client(tmp_path):
    provider=Recorder()
    app=create_app(tmp_path/'test.sqlite',provider,TOKEN)
    async with AsyncClient(transport=ASGITransport(app=app),base_url='http://test',headers={'Authorization':'Bearer '+TOKEN}) as c:
        yield c,app,provider
async def test_auth_origin_and_strict_validation(client):
    c,_,_=client
    assert (await c.get('/health',headers={'Authorization':'bad'})).status_code==401
    assert (await c.get('/health',headers={'Origin':'https://evil.test'})).status_code==403
    assert (await c.post('/chat',json={'conversation':'a','text':'','shell':'rm'})).status_code==422
async def test_stream_and_persistence(client):
    c,app,p=client
    r=await c.post('/chat',json={'conversation':'a','text':'hi'})
    events=[json.loads(x) for x in r.text.splitlines()]
    assert [e['type'] for e in events]==['start','delta','delta','done']
    assert (await c.get('/conversations/a')).json()==[{'role':'user','text':'hi','state':'complete'},{'role':'assistant','text':'hello world','state':'complete'}]
    assert (await c.delete('/conversations/a')).json()['deleted']
    assert (await c.get('/conversations/a')).json()==[]
async def test_memory_explicit_relevant_scoped_and_forget(client):
    c,app,p=client
    one=(await c.post('/memories',json={'conversation':'a','fact':'My favorite color is blue.'})).json()['id']
    await c.post('/memories',json={'conversation':'a','fact':'My pet is named Snow.'})
    await c.post('/memories',json={'conversation':'b','fact':'My favorite color is red.'})
    await c.post('/chat',json={'conversation':'a','text':'What is my favorite color?'})
    prompt=p.messages[0]['content']
    assert 'blue' in prompt and 'red' not in prompt and 'Snow' not in prompt
    assert len((await c.get('/memories/export')).json()['memories'])==3
    assert (await c.delete('/memories/'+one)).status_code==200
    await c.post('/chat',json={'conversation':'a','text':'What is my favorite color?'})
    assert 'blue' not in p.messages[0]['content']
    assert len((await c.get('/memories')).json())==2
async def test_actions_exact_single_use_and_receipt(client):
    c,app,_=client
    body={'action':{'kind':'open_app','package':'com.android.settings'}}
    draft=(await c.post('/actions/prepare',json=body)).json()
    id=draft['id']
    assert (await c.post('/actions/'+id+'/approve',json={'token':'z'*32})).status_code==409
    result=await c.post('/actions/'+id+'/approve',json={'token':draft['approval_token']})
    assert result.json()['executed'] is False
    assert result.json()['action']==body['action']
    assert (await c.post('/actions/'+id+'/approve',json={'token':draft['approval_token']})).status_code==409
    receipt=await c.post('/actions/'+id+'/receipt',json={'result':'opened','detail':'device reported startActivity accepted'})
    assert receipt.json()['independently_verified'] is False
    assert (await c.post('/actions/'+id+'/receipt',json={'result':'opened','detail':'duplicate'})).status_code==409
async def test_actions_no_shell_extra_keys_or_unsupported_packages(client):
    c,app,_=client
    for action in [{'kind':'shell','command':'echo hi'},{'kind':'open_app','package':'com.bad.app'},{'kind':'open_app','package':'com.android.settings','command':'echo hi'},{'kind':'reminder','title':'Hi','at_ms':0}]:
        assert (await c.post('/actions/prepare',json={'action':action})).status_code==422
    draft=(await c.post('/actions/prepare',json={'action':{'kind':'reminder','title':'Study','at_ms':int(time.time()*1000)+60000}})).json()
    with app.state.store.db() as db: db.execute('UPDATE actions SET expires=0 WHERE id=?',(draft['id'],))
    assert (await c.post('/actions/'+draft['id']+'/approve',json={'token':draft['approval_token']})).status_code==409
async def test_rate_limit(client):
    c,_,_=client
    for n in range(10): assert (await c.post('/chat',json={'conversation':'a','text':str(n)})).status_code==200
    r=await c.post('/chat',json={'conversation':'a','text':'11'})
    assert r.status_code==429 and r.headers['retry-after']=='60'
async def test_failure_and_unconfigured(tmp_path):
    app=create_app(tmp_path/'a',Recorder(True),TOKEN)
    async with AsyncClient(transport=ASGITransport(app=app),base_url='http://test',headers={'Authorization':'Bearer '+TOKEN}) as c:
        r=await c.post('/chat',json={'conversation':'a','text':'hi'})
        assert json.loads(r.text.splitlines()[-1])['type']=='error'
        assert (await c.get('/conversations/a')).json()[-1]['state']=='failed'
    app=create_app(tmp_path/'b',token=TOKEN)
    async with AsyncClient(transport=ASGITransport(app=app),base_url='http://test',headers={'Authorization':'Bearer '+TOKEN}) as c:
        assert (await c.post('/chat',json={'conversation':'a','text':'hi'})).status_code==503
        assert (await c.get('/health')).json()['provider_configured'] is False

class FakeVoice:
    def __init__(self): self.calls=[]
    async def synthesize(self, text, style):
        self.calls.append((text,style))
        return b"fake-mp3-audio"

async def test_voice_requires_configuration_auth_and_explicit_valid_payload(tmp_path):
    app=create_app(tmp_path/"voice-off",token=TOKEN)
    async with AsyncClient(transport=ASGITransport(app=app),base_url="http://test",headers={"Authorization":"Bearer "+TOKEN}) as c:
        assert (await c.post("/voice/speech",json={"text":"hello","style":"curious"})).status_code==503
        assert (await c.post("/voice/speech",json={"text":"hello"},headers={"Authorization":"bad"})).status_code==401
        assert (await c.post("/voice/speech",json={"text":"hello","style":"invented"})).status_code==422
        assert (await c.post("/voice/speech",json={"text":"hello","style":"neutral","api_key":"leak"})).status_code==422
    voice=FakeVoice(); app=create_app(tmp_path/"voice-on",token=TOKEN,voice_provider=voice)
    async with AsyncClient(transport=ASGITransport(app=app),base_url="http://test",headers={"Authorization":"Bearer "+TOKEN}) as c:
        response=await c.post("/voice/speech",json={"text":"A reply","style":"whispering"})
        assert response.status_code==200
        assert response.headers["content-type"]=="audio/mpeg"
        assert response.headers["cache-control"]=="no-store"
        assert response.content==b"fake-mp3-audio"
        assert voice.calls==[("A reply","whispering")]

async def test_elevenlabs_adapter_uses_server_key_and_official_tag_without_live_calls(monkeypatch):
    import httpx
    original=httpx.AsyncClient
    seen=[]
    def handler(request):
        seen.append(request)
        assert request.url.host=="api.elevenlabs.io"
        assert request.url.path=="/v1/text-to-speech/voice_12345678"
        assert request.url.query==b"output_format=mp3_44100_128"
        assert request.headers["xi-api-key"]=="server-secret-test-only"
        payload=json.loads(request.content)
        assert payload=={"text":"[curious] Is this working?","model_id":"eleven_v4"}
        return httpx.Response(200,content=b"mock-audio",headers={"content-type":"audio/mpeg"})
    monkeypatch.setattr(httpx,"AsyncClient",lambda **kw:original(transport=httpx.MockTransport(handler),**kw))
    voice=__import__("app").ElevenLabsVoice("server-secret-test-only","voice_12345678")
    assert await voice.synthesize("Is this working?","curious")==b"mock-audio"
    assert len(seen)==1

def test_token_and_provider_host(tmp_path):
    with pytest.raises(ValueError): create_app(tmp_path/'a',token='short')
    with pytest.raises(ValueError): Ollama('model','https://public.example')

@pytest.mark.parametrize('url', ['ftp://localhost','http://user:pass@localhost','http://127.0.0.1/path','http://localhost?token=oops','http://localhost#fragment'])
def test_provider_rejects_non_origin_and_credential_urls(url):
    with pytest.raises(ValueError): Ollama('model',url)

async def test_local_adapter_requires_completion_and_keeps_memory_input_local(monkeypatch):
    import httpx
    original=httpx.AsyncClient
    seen=[]
    def handler(request):
        seen.append(json.loads(request.content))
        assert request.url.host=='127.0.0.1' and request.url.path=='/api/chat'
        return httpx.Response(200,text='{"message":{"content":"blue"}}\n{"done":true}\n')
    monkeypatch.setattr(httpx,'AsyncClient',lambda **kw: original(transport=httpx.MockTransport(handler),**kw))
    p=Ollama('installed-model','http://127.0.0.1:11434')
    messages=[{'role':'user','content':'favorite color?'}]
    assert [x async for x in p.stream(messages)]==['blue']
    assert seen[0]['messages']==messages and seen[0]['stream'] is True
    monkeypatch.setattr(httpx,'AsyncClient',lambda **kw: original(transport=httpx.MockTransport(lambda request:httpx.Response(200,text='{"message":{"content":"partial"}}\n')),**kw))
    with pytest.raises(RuntimeError,match='before completion'):
        _=[x async for x in p.stream(messages)]

async def test_cancelled_request_releases_active_scope_without_completed_reply(tmp_path):
    class Waiting:
        def __init__(self): self.started=asyncio.Event()
        async def stream(self,messages):
            yield 'partial'
            self.started.set()
            await asyncio.sleep(30)
            yield 'never'
    p=Waiting(); app=create_app(tmp_path/'cancel',p,TOKEN)
    async with AsyncClient(transport=ASGITransport(app=app),base_url='http://test',headers={'Authorization':'Bearer '+TOKEN}) as c:
        pending=asyncio.create_task(c.post('/chat',json={'conversation':'a','text':'hi'}))
        await asyncio.wait_for(p.started.wait(),2)
        assert (await c.post('/chat',json={'conversation':'a','text':'overlap'})).status_code==409
        assert (await c.delete('/conversations/a')).status_code==409
        pending.cancel()
        with pytest.raises(asyncio.CancelledError): await pending
        history=(await c.get('/conversations/a')).json()
        assert history[-1]=={'role':'assistant','text':'partial','state':'interrupted'}
        assert (await c.delete('/conversations/a')).status_code==200

async def test_history_index_reopens_scopes_and_removes_deleted(client):
    c,_,_=client
    await c.post('/chat',json={'conversation':'earlier','text':'Remember this chat'})
    await c.post('/chat',json={'conversation':'latest','text':'Recent question'})
    rows=(await c.get('/conversations')).json()
    assert [r['conversation'] for r in rows]==['latest','earlier']
    assert rows[1]['title']=='Remember this chat' and rows[1]['message_count']==2
    assert (await c.get('/conversations/earlier')).json()[0]['text']=='Remember this chat'
    assert (await c.delete('/conversations/earlier')).json()['deleted'] is True
    assert [r['conversation'] for r in (await c.get('/conversations')).json()]==['latest']

async def test_unknown_receipt_is_distinct_and_success_kind_is_validated(client):
    c,app,_=client
    draft=(await c.post('/actions/prepare',json={'action':{'kind':'open_app','package':'com.android.settings'}})).json()
    await c.post('/actions/'+draft['id']+'/approve',json={'token':draft['approval_token']})
    assert (await c.post('/actions/'+draft['id']+'/receipt',json={'result':'scheduled','detail':'wrong kind'})).status_code==422
    reply=await c.post('/actions/'+draft['id']+'/receipt',json={'result':'unknown','detail':'Device disconnected; no automatic retry'})
    assert reply.json()['result']=='unknown' and reply.json()['independently_verified'] is False
    assert (await c.post('/actions/'+draft['id']+'/receipt',json={'result':'opened','detail':'late duplicate'})).status_code==409
