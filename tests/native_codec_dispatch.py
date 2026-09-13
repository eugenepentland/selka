"""Internal declared-codec calls preserve a live native caller and shared budgets."""
from pathlib import Path

DATA = '''module data;export Wire;export Positive;export Decoded;EXPORT_REJECTION
fn unused<T:copy>(x:T)->T{return x;}
struct Wire{n:i64}REJECTION
result Decoded{ok:Positive,err:ERROR_TYPE}
domain Positive:i64{
 codec Wire{decode:from_wire,encode:to_wire}
 private fn raw(n:i64)->Positive{return wrap<Positive>(n);}
 fn from_wire(x:Wire)->Decoded{
  if x.n==99{return new Decoded.ok(Positive.raw(1/(x.n-99)));}
  if x.n<=0{return new Decoded.err(ERROR_VALUE);}
  return new Decoded.ok(Positive.raw(x.n*2));
 }
 fn to_wire(x:Positive)->Wire{return new Wire{n:unwrap(x)+1};}
}
'''
MAIN = '''module main;import data;
result Time{ok:i64,err:i64}
fn main(c:clock_cap)->i64{match clock_now<Time>(c){Time.ok(n)=>{return n;},Time.err(e)=>{return e;}}}
'''
HOST = r'''
static int mode;
static size_t identity(const char *name) {
    for(size_t i=0;i<sizeof names/sizeof *names;++i) if(!strcmp(names[i],name)) return i;
    assert(0);return 0;
}
static Slot decoded_payload(Slot value, size_t tag) {
    assert((value.object ? value.object->tag : (size_t)((U)value.number & 1))==tag);
    Slot payload=value.object ? field_value(value,0) : (Slot){variant_payload(value.number,1,64,1),NULL};
    release_value(value);return payload;
}
static MylangClockResult clock_value(void *context) {
    (void)context;
    if(mode==2) {
        Slot unexpected=invoke_codec(identity("data::Positive.raw"),(Slot){7,NULL});
        release_value(unexpected);assert(0);
    }
    size_t caller_values=nv,caller_frames=nf;
    push(123);make_record(1,NULL); /* a caller-owned operand survives every codec */
    push(mode==1 ? 99 : 7);make_record(1,NULL);
    Slot positive=decoded_payload(invoke_codec(identity("data::Positive.from_wire"),values[--nv]),0);
    assert(positive.number==14 && !positive.object);
    Slot encoded=invoke_codec(identity("data::Positive.to_wire"),positive);
    assert(encoded.object && encoded.object->count==1 && encoded.object->fields[0].number==15);
    release_value(encoded);
    push(-1);make_record(1,NULL);
    Slot rejected=decoded_payload(invoke_codec(identity("data::Positive.from_wire"),values[--nv]),1);
    if(BOXED) assert(rejected.object && rejected.object->fields[0].number==-10);
    else assert(rejected.number==-10 && !rejected.object);
    release_value(rejected);
    assert(nv==caller_values+1 && nf==caller_frames && values[nv-1].object->fields[0].number==123);
    release_value(values[--nv]);
    return (MylangClockResult){MYLANG_PROVIDER_OK,15};
}
int main(void) {
    MylangNativeProviders providers={.clock_now=clock_value};
    MylangRunOptions options={.providers=&providers};MylangRunResult result;
    for(unsigned i=0;i<32;++i) assert(mylang_native_run_v1(&options,&result)==0 && result.value==15 && live==0);
    uint64_t steps=result.steps;assert(steps>10);
    options.max_steps=steps-1;
    assert(mylang_native_run_v1(&options,&result)==1 && !strcmp(result.code,"R_STEP_LIMIT") && live==0);
    options.max_steps=0;options.max_frames=2;
    assert(mylang_native_run_v1(&options,&result)==1 && !strcmp(result.code,"R_FRAME_LIMIT") && live==0);
    options.max_frames=3;
    assert(mylang_native_run_v1(&options,&result)==0 && result.value==15 && live==0);
    options.max_frames=0;
    mode=1;
    assert(mylang_native_run_v1(&options,&result)==1 && !strcmp(result.code,"R_DIVISION_BY_ZERO") && live==0);
    assert(result.frame_count==2 && !strcmp(result.frames[0].function,"data::Positive.from_wire") && !strcmp(result.frames[1].function,"main::main"));
    mode=2;
    assert(mylang_native_run_v1(&options,&result)==2 && !strcmp(result.code,"InternalError") && live==0);
    mode=0;attempts=0;
    assert(mylang_native_run_v1(&options,&result)==0 && live==0);
    size_t allocations=attempts;
    for(size_t i=0;i<allocations;++i){
        attempts=0;fail_at=i;
        assert(mylang_native_run_v1(&options,&result)==2 && !strcmp(result.code,"OutOfMemory") && live==0);
        fail_at=(size_t)-1;
        assert(mylang_native_run_v1(&options,&result)==0 && result.value==15 && live==0);
    }
    return 0;
}
'''
