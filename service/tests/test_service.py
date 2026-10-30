import asyncio
import json
import time
import pytest
import httpx
from httpx import ASGITransport, AsyncClient
from app import create_app, Ollama, GroqProvider
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
        assert request.url.path=="/v1/text-to-speech/test_voice"
        assert request.url.query==b"output_format=mp3_44100_128"
        assert request.headers["xi-api-key"]=="unit-test-key"
        payload=json.loads(request.content)
        assert payload=={"text":"[curious] Is this working?","model_id":"eleven_v4"}
        return httpx.Response(200,content=b"mock-audio",headers={"content-type":"audio/mpeg"})
    monkeypatch.setattr(httpx,"AsyncClient",lambda **kw:original(transport=httpx.MockTransport(handler),**kw))
    voice=__import__("app").ElevenLabsVoice("unit-test-key","test_voice")
    assert await voice.synthesize("Is this working?","curious")==b"mock-audio"
    assert len(seen)==1

def test_token_and_provider_host(tmp_path):
    with pytest.raises(ValueError): create_app(tmp_path/'a',token='short')
    with pytest.raises(ValueError): Ollama('model','https://public.example')

@pytest.mark.parametrize('url', ['ftp://localhost','http://user:pass@localhost','http://127.0.0.1/path','http://localhost?token=oops','http://localhost#fragment'])
def test_provider_rejects_non_origin_and_credential_urls(url):
    with pytest.raises(ValueError): Ollama('model',url)

def test_groq_configuration_is_explicit_and_never_falls_back(monkeypatch, tmp_path):
    monkeypatch.delenv("ASSISTANT_PROVIDER", raising=False)
    monkeypatch.delenv("OLLAMA_MODEL", raising=False)
    monkeypatch.setenv("GROQ_API_KEY", "unit-test-key")
    # Merely having a Groq key present must not enable a network provider.
    default_app = create_app(tmp_path / "default", token=TOKEN)
    assert default_app.state.provider.__class__.__name__ == "Unconfigured"
    assert default_app.state.provider_configured is False

    monkeypatch.setenv("ASSISTANT_PROVIDER", "groq")
    app = create_app(tmp_path / "groq", token=TOKEN)
    assert isinstance(app.state.provider, GroqProvider)
    assert app.state.provider.model == "openai/gpt-oss-120b"
    assert app.state.provider_configured is True

    monkeypatch.delenv("GROQ_API_KEY")
    with pytest.raises(ValueError, match="GROQ_API_KEY"):
        create_app(tmp_path / "missing-key", token=TOKEN)
    monkeypatch.setenv("ASSISTANT_PROVIDER", "unknown")
    with pytest.raises(ValueError, match="ASSISTANT_PROVIDER"):
        create_app(tmp_path / "unknown", token=TOKEN)


def test_groq_provider_validates_key_and_model():
    with pytest.raises(ValueError, match="GROQ_API_KEY"):
        GroqProvider("", "openai/gpt-oss-120b")
    with pytest.raises(ValueError, match="model identifier"):
        GroqProvider("test-key", "../outside")


async def test_groq_adapter_streams_from_fixed_endpoint_without_live_calls(monkeypatch):
    import httpx
    original = httpx.AsyncClient
    seen = []
    def handler(request):
        seen.append(request)
        assert str(request.url) == GroqProvider.URL
        assert request.headers["authorization"] == "Bearer unit-test-key"
        payload = json.loads(request.content)
        assert payload == {
            "model": "openai/gpt-oss-120b",
            "messages": [{"role": "user", "content": "hello"}],
            "stream": True,
            "max_completion_tokens": 2048,
        }
        body = (
            'data: {"choices":[{"delta":{"content":"Hello "},"finish_reason":null}]}\n\n'
            'data: {"choices":[{"delta":{"content":"world"},"finish_reason":null}]}\n\n'
            'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n'
            'data: [DONE]\n\n'
        )
        return httpx.Response(200, content=body, headers={"content-type": "text/event-stream"})
    monkeypatch.setattr(httpx, "AsyncClient", lambda **kwargs: original(transport=httpx.MockTransport(handler), **kwargs))
    provider = GroqProvider("unit-test-key", "openai/gpt-oss-120b")
    messages = [{"role": "user", "content": "hello"}]
    assert [part async for part in provider.stream(messages)] == ["Hello ", "world"]
    assert len(seen) == 1


async def test_groq_adapter_assembles_multiline_sse_data_and_ignores_comments(monkeypatch):
    import httpx
    original = httpx.AsyncClient
    body = (
        ": heartbeat\r\n"
        "event: message\r\n"
        'data: {"choices":[\r\n'
        'data: {"delta":{"content":"Hello"},"finish_reason":"stop"}\r\n'
        "data: ]}\r\n\r\n"
        "data: [DONE]\r\n\r\n"
    )
    monkeypatch.setattr(
        httpx,
        "AsyncClient",
        lambda **kwargs: original(
            transport=httpx.MockTransport(
                lambda request: httpx.Response(
                    200, content=body, headers={"content-type": "text/event-stream"}
                )
            ),
            **kwargs,
        ),
    )
    provider = GroqProvider("unit-test-key", "openai/gpt-oss-120b")
    assert [part async for part in provider.stream([{"role": "user", "content": "hello"}])] == ["Hello"]


async def test_groq_adapter_fails_closed_on_http_errors_and_truncated_streams(monkeypatch):
    import httpx
    original = httpx.AsyncClient
    provider = GroqProvider("unit-test-key", "openai/gpt-oss-120b")
    messages = [{"role": "user", "content": "private prompt"}]

    def error_handler(request):
        return httpx.Response(401, content="secret-bearing error body")
    monkeypatch.setattr(httpx, "AsyncClient", lambda **kwargs: original(transport=httpx.MockTransport(error_handler), **kwargs))
    with pytest.raises(RuntimeError, match="Groq API request failed") as error:
        _ = [part async for part in provider.stream(messages)]
    assert "private prompt" not in str(error.value)
    assert "secret-bearing" not in str(error.value)

    def partial_handler(request):
        return httpx.Response(200, content='data: {"choices":[{"delta":{"content":"partial"},"finish_reason":null}]}\n', headers={"content-type": "text/event-stream"})
    monkeypatch.setattr(httpx, "AsyncClient", lambda **kwargs: original(transport=httpx.MockTransport(partial_handler), **kwargs))
    with pytest.raises(RuntimeError, match="before completion"):
        _ = [part async for part in provider.stream(messages)]


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

class FakeImage:
    def __init__(self, image=bytes.fromhex("89504e470d0a1a0a")+b"mock-image"):
        self.calls=[]; self.image=image
    async def generate(self, prompt):
        self.calls.append(prompt)
        return self.image, "image/png"

async def test_image_route_is_disabled_by_default_and_sends_only_explicit_prompt(tmp_path):
    app=create_app(tmp_path/"image-off",token=TOKEN)
    async with AsyncClient(transport=ASGITransport(app=app),base_url="http://test",headers={"Authorization":"Bearer "+TOKEN}) as c:
        assert (await c.get('/health')).json()['image_provider_configured'] is False
        assert (await c.post('/images/generate',json={'prompt':'a blue fox'})).status_code==503
        assert (await c.post('/images/generate',json={'prompt':'x','conversation':'personal'})).status_code==422
        assert (await c.post('/images/generate',json={'prompt':'x'},headers={'Authorization':'bad'})).status_code==401
        assert (await c.post('/images/generate',json={'prompt':'x'*1001})).status_code==422
    image=FakeImage(); app=create_app(tmp_path/"image-on",token=TOKEN,image_provider=image)
    async with AsyncClient(transport=ASGITransport(app=app),base_url="http://test",headers={"Authorization":"Bearer "+TOKEN}) as c:
        response=await c.post('/images/generate',json={'prompt':'a blue fox'})
        assert response.status_code==200
        assert response.headers['content-type']=='image/png'
        assert response.headers['cache-control']=='no-store'
        assert response.content.startswith(bytes.fromhex('89504e47'))
        assert image.calls==['a blue fox']

async def test_cloudflare_flux_adapter_uses_server_key_and_prompt_only():
    import base64
    from app import CloudflareFluxImageProvider
    png=base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jXioAAAAASUVORK5CYII=')
    observed=[]
    async def handle(request):
        observed.append(request)
        return httpx.Response(200,headers={'content-type':'application/json'},json={'result':{'image':base64.b64encode(png).decode()}})
    provider=CloudflareFluxImageProvider('0123456789abcdef0123456789abcdef','server-secret',httpx.MockTransport(handle))
    image,mime=await provider.generate('only the prompt')
    assert image==png and mime=='image/png'
    req=observed[0]
    assert req.url.path.endswith('/@cf/black-forest-labs/flux-1-schnell')
    assert req.headers['authorization']=='Bearer server-secret'
    assert req.read().decode()=='{"prompt":"only the prompt"}'

async def test_cloudflare_adapter_rejects_provider_error_and_malformed_image():
    import base64
    from app import CloudflareFluxImageProvider
    async def bad_status(request): return httpx.Response(429,text='private provider body')
    provider=CloudflareFluxImageProvider('0123456789abcdef0123456789abcdef','server-secret',httpx.MockTransport(bad_status))
    with pytest.raises(RuntimeError,match='request failed'):
        await provider.generate('prompt')
    async def bad_image(request): return httpx.Response(200,headers={'content-type':'application/json'},json={'result':{'image':base64.b64encode(b'not-image').decode()}})
    provider=CloudflareFluxImageProvider('0123456789abcdef0123456789abcdef','server-secret',httpx.MockTransport(bad_image))
    with pytest.raises(RuntimeError,match='unusable image'):
        await provider.generate('prompt')


def test_cloudflare_image_provider_is_opt_in_and_validates_server_configuration(monkeypatch, tmp_path):
    from app import CloudflareFluxImageProvider
    monkeypatch.setenv("ASSISTANT_IMAGE_PROVIDER", "disabled")
    monkeypatch.setenv("CLOUDFLARE_ACCOUNT_ID", "0123456789abcdef0123456789abcdef")
    monkeypatch.setenv("CLOUDFLARE_API_TOKEN", "unit-test-key")
    disabled = create_app(tmp_path / "cloudflare-disabled", token=TOKEN)
    assert disabled.state.image_provider is None
    monkeypatch.setenv("ASSISTANT_IMAGE_PROVIDER", "cloudflare")
    enabled = create_app(tmp_path / "cloudflare-enabled", token=TOKEN)
    assert isinstance(enabled.state.image_provider, CloudflareFluxImageProvider)
    monkeypatch.setenv("CLOUDFLARE_ACCOUNT_ID", "bad")
    with pytest.raises(ValueError, match="CLOUDFLARE_ACCOUNT_ID"):
        create_app(tmp_path / "cloudflare-invalid", token=TOKEN)
    monkeypatch.setenv("ASSISTANT_IMAGE_PROVIDER", "unknown")
    with pytest.raises(ValueError, match="ASSISTANT_IMAGE_PROVIDER"):
        create_app(tmp_path / "cloudflare-unknown", token=TOKEN)
