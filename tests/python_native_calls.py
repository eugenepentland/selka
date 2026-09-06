"""Generated Python wrappers invoke pinned native libraries without compiler processes."""
import argparse
from pathlib import Path
import shutil
import sys
import tempfile
from native_embedding import invoke
from python_calls import load, fails

SOURCE = '''module main;import data;
export domain_echo;export domain_pair;export DomainPair;export Rejection;export Checked;export Decoded;export checked_echo;export checked_many;
export Pair;export Color;export U;export make;export change;export echo;export unsigned;export boolean;export variant;export table_value;export divide;export depth;
struct Rejection{code:[4]i64}
result Decoded{ok:Checked,err:Rejection}
domain Checked:i64{
 codec data::Wire{decode:from_wire,encode:to_wire}
 fn from_wire(x:data::Wire)->Decoded{
  if x.n<=0{return new Decoded.err(new Rejection{code:new [4]i64[-10,-10,-10,-10]});}
  if x.n==99{return new Decoded.ok(wrap<Checked>(1/(x.n-99)));}
  return new Decoded.ok(wrap<Checked>(x.n*2));
 }
 fn to_wire(x:Checked)->data::Wire{
  if unwrap(x)==26{return new data::Wire{n:1/(unwrap(x)-26)};}
  return new data::Wire{n:unwrap(x)+1};
 }
}
fn checked_echo(x:Checked)->Checked{return x;}
fn checked_many(x:Checked)->[2]Checked{return new [2]Checked[x,x];}
struct DomainPair{items:[2]data::Positive}
fn domain_echo(x:data::Positive)->data::Positive{return x;}
fn domain_pair(x:DomainPair)->DomainPair{return x;}
enum Color{red,blue}struct Pair{values:[2]i64,color:Color}union U{none,value:Pair}
fn make()->Pair{return new Pair{values:new [2]i64[7,8],color:new Color.blue};}
fn change(p:Pair)->Pair{return update(p){values:replace(p.values,0,9)};}
fn echo(x:i64)->i64{return x;}
fn unsigned(x:u64)->u64{return x;}
fn boolean(x:bool)->bool{return !x;}
fn variant(p:Pair)->U{return new U.value(p);}
fn table_value()->[Color]u16{return new [Color]u16{red:200u16,blue:404u16};}
fn divide(x:i64)->i64{return 1/x;}
fn depth(n:i64)->i64{if n==0{return 7;}return depth(n-1);}
fn main()->i64{return 0;}
'''


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--compiler',required=True,type=Path)
    parser.add_argument('--zig',required=True)
    args=parser.parse_args()
    repository=Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix='mylang-python-native-') as directory:
        root=Path(directory)
        project=root/'project';project.mkdir()
        entry=project/'main.my';entry.write_text(SOURCE)
        shutil.copyfile(repository/'examples/domain-codecs/data.my',project/'data.my')
        generated=root/'bindings.py'
        invoke([sys.executable,repository/'scripts/bindings.py',entry,'--compiler',args.compiler,'--output',generated])
        bindings=load(generated)
        vm=bindings.Client(str(args.compiler.resolve()),str(entry))
        values=bindings.CALL_FIELDS['main::Pair']['values']
        color=bindings.CALL_FIELDS['main::Pair']['color']
        pair=bindings.CALL_TYPES['main::Pair'](**{values:(7,8),color:bindings.CALL_TYPES['main::Color']('blue')})
        wire=bindings.CALL_TYPES['data::Wire'](**{bindings.CALL_FIELDS['data::Wire']['n']:7})
        positive=bindings.CALL_TYPES['data::Positive'](wire)
        domain_pair=bindings.CALL_TYPES['main::DomainPair'](**{bindings.CALL_FIELDS['main::DomainPair']['items']:(positive,positive)})
        checked=bindings.CALL_TYPES['main::Checked'](wire)
        fixtures=[('main::checked_echo',(checked,)),('main::domain_echo',(positive,)),('main::domain_pair',(domain_pair,)),
                  ('data::Positive.from_wire',(wire,)),('data::Positive.to_wire',(positive,)),('main::make',()),('main::change',(pair,)),('main::echo',(-9223372036854775808,)),
                  ('main::unsigned',(18446744073709551615,)),('main::boolean',(True,)),
                  ('main::variant',(pair,)),('main::table_value',()),('main::depth',(20,))]
        expected=[bindings.CALLS[name](vm,*arguments) for name,arguments in fixtures]
        for mode in ('Debug','ReleaseFast'):
            library=root/f'{mode}.so'
            invoke([sys.executable,repository/'scripts/native.py',entry,'--project','--library','--mode',mode,'--compiler',args.compiler,'--zig',args.zig,'-o',library])
            client=bindings.NativeClient(library)
            for (name,arguments),value in zip(fixtures,expected):
                assert bindings.CALLS[name](client,*arguments)==value,name
            assert getattr(pair,values)==(7,8)
            assert getattr(client.call('main::checked_echo',x=checked).wire,bindings.CALL_FIELDS['data::Wire']['n'])==15
            def checked_value(n):
                return bindings.CALL_TYPES['main::Checked'](bindings.CALL_TYPES['data::Wire'](**{bindings.CALL_FIELDS['data::Wire']['n']:n}))
            error=fails(bindings.CallError,'DomainCodecRejected',lambda:client.call('main::checked_echo',x=checked_value(-1)))
            rejection=bindings.CALL_TYPES['main::Rejection'](**{bindings.CALL_FIELDS['main::Rejection']['code']:(-10,-10,-10,-10)})
            assert error.rejection==rejection and error.domain=='main::Checked'
            for n,frame in ((99,'main::Checked.from_wire'),(13,'main::Checked.to_wire')):
                error=fails(bindings.CallError,'R_DIVISION_BY_ZERO',lambda:client.call('main::checked_echo',x=checked_value(n)))
                assert error.domain=='main::Checked' and frame in error.diagnostics
            real_codec=client._codec_call
            def malformed_codec(*arguments):
                status=real_codec(*arguments)
                arguments[3][0].children=0
                return status
            client._codec_call=malformed_codec
            fails(bindings.CallError,'InvalidNativeResult',lambda:client.call('main::checked_echo',x=checked))
            fails(bindings.CallError,'InvalidNativeResult',lambda:client.call('main::checked_echo',x=checked_value(-1)))
            client._codec_call=real_codec
            error=fails(bindings.CallError,'R_DIVISION_BY_ZERO',lambda:client.call('main::divide',x=0))
            assert 'main::divide' in error.diagnostics and error.returncode==1
            assert client.call('main::echo',x=7)==7
            real_call=client._call
            def malformed(*arguments):
                status=real_call(*arguments)
                arguments[3][0].children=100001
                return status
            client._call=malformed
            fails(bindings.CallError,'InvalidNativeResult',lambda:client.call('main::make'))
            client._call=real_call
            fails(bindings.CodecError,'ValueTypeMismatch',lambda:client.call('main::boolean',x=1))
            fails(bindings.CodecError,'UnknownFunction',lambda:client.call('private'))
            assert 'data::Positive.from_wire' in bindings.NATIVE_FUNCTION_NAMES
            negative_wire=bindings.CALL_TYPES['data::Wire'](**{bindings.CALL_FIELDS['data::Wire']['n']:-1})
            negative=bindings.CALL_TYPES['data::Positive'](negative_wire)
            error=fails(bindings.CallError,'DomainCodecRejected',lambda:client.call('main::domain_echo',x=negative))
            assert error.domain=='data::Positive' and error.rejection==-1 and error.rejected and error.calls==1
            assert bindings.CALLS['data::Positive.from_wire'](client,negative_wire)==bindings.CALLS['data::Positive.from_wire'](vm,negative_wire)
            codec_call=client._codec_call;client._codec_call=None
            assert client.call('main::echo',x=7)==7
            fails(bindings.CallError,'NativeABIUnavailable',lambda:client.call('main::domain_echo',x=positive))
            client._codec_call=codec_call
            limited=bindings.NativeClient(library,limits=bindings.NativeLimits(max_calls=2))
            error=fails(bindings.CallError,'CodecCallLimit',lambda:limited.call('main::domain_echo',x=positive))
            assert error.calls==2 and error.domain=='data::Positive' and error.rejection is None
            limited=bindings.NativeClient(library,limits=bindings.NativeLimits(max_calls=3))
            assert limited.call('main::domain_echo',x=positive)==positive
            limited=bindings.NativeClient(library,limits=bindings.NativeLimits(max_depth=2))
            fails(bindings.CodecError,'CodecDepthLimit',lambda:limited.call('main::domain_echo',x=positive))
            small_codec=bindings.NativeClient(library,limits=bindings.NativeLimits(max_nodes=3))
            codec_attempts=[];actual_codec=small_codec._codec_call
            def tracked_codec(*arguments):
                codec_attempts.append(1);return actual_codec(*arguments)
            small_codec._codec_call=tracked_codec
            error=fails(bindings.CallError,'OutputTooSmall',lambda:small_codec.call('main::checked_many',x=checked))
            assert len(codec_attempts)==1 and error.calls==4 and 'required output nodes: 7' in error.diagnostics
            error=fails(bindings.CallError,'OutputTooSmall',lambda:small_codec.call('main::checked_echo',x=checked_value(-1)))
            assert len(codec_attempts)==2 and error.calls==1 and error.rejected and error.rejection is None
            assert error.domain=='main::Checked' and 'required output nodes: 6' in error.diagnostics
            small=bindings.NativeClient(library,limits=bindings.NativeLimits(max_nodes=1))
            calls=[];actual=small._call
            def tracked(*arguments):
                calls.append(1);return actual(*arguments)
            small._call=tracked
            error=fails(bindings.CallError,'OutputTooSmall',lambda:small.call('main::make'))
            assert len(calls)==1 and 'required output nodes:' in error.diagnostics
            limited=bindings.NativeClient(library,limits=bindings.NativeLimits(max_steps=1))
            fails(bindings.CallError,'R_STEP_LIMIT',lambda:limited.call('main::make'))
            limited=bindings.NativeClient(library,limits=bindings.NativeLimits(max_depth=1))
            fails(bindings.CodecError,'CodecDepthLimit',lambda:limited.call('main::make'))
            limited=bindings.NativeClient(library,limits=bindings.NativeLimits(max_frames=4))
            fails(bindings.CallError,'R_FRAME_LIMIT',lambda:limited.call('main::depth',n=20))
        for options in ({'max_nodes':100001},{'max_depth':129},{'max_steps':0},{'max_frames':True},{'max_calls':0},{'max_calls':True}):
            fails(bindings.CodecError,'InvalidNativeLimits',lambda:bindings.NativeLimits(**options))
        entry.write_text(SOURCE.replace('values:[2]i64,color:Color','color:Color,values:[2]i64'))
        mismatch=root/'mismatch.so'
        invoke([sys.executable,repository/'scripts/native.py',entry,'--project','--library','--compiler',args.compiler,'--zig',args.zig,'-o',mismatch])
        fails(bindings.CallError,'NativeSchemaMismatch',lambda:bindings.NativeClient(mismatch))
        scalar=root/'scalar.my';scalar.write_text('fn main()->i64{return 0;}')
        absent=root/'absent.so'
        invoke([sys.executable,repository/'scripts/native.py',scalar,'--library','--compiler',args.compiler,'--zig',args.zig,'-o',absent])
        fails(bindings.CallError,'NativeSchemaUnavailable',lambda:bindings.NativeClient(absent))
        fails(bindings.CallError,'NativeLibraryIO',lambda:bindings.NativeClient(root/'missing.so'))
        stub=root/'stub.c';stub.write_text('int marker(void){return 0;}')
        no_api=root/'no-api.so'
        invoke([args.zig,'cc','-shared','-fPIC',stub,'-o',no_api])
        fails(bindings.CallError,'NativeABIUnavailable',lambda:bindings.NativeClient(no_api))
        shutil.rmtree(project)
        # Existing generated wrappers and library remain sufficient after source removal.
        assert getattr(bindings.CALLS['main::change'](client,pair),values)==(9,8)
        assert client.call('main::domain_echo',x=positive)==positive
    print('Python native bindings: typed VM/native agreement, nested domains, scalar/record rejections, codec traps/quotas, no-retry success/rejection capacity errors, schema checks and source-independent calls passed')


if __name__=='__main__':
    main()
