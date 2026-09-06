"""Generated Python wrappers invoke pinned native libraries without compiler processes."""
import argparse
from pathlib import Path
import shutil
import sys
import tempfile
from native_embedding import invoke
from python_calls import load, fails

SOURCE = '''module main;import data;
export Pair;export Color;export U;export make;export change;export echo;export unsigned;export boolean;export variant;export table_value;export divide;export depth;
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
        fixtures=[('main::make',()),('main::change',(pair,)),('main::echo',(-9223372036854775808,)),
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
            assert all(not name.startswith('data::Positive.') for name in bindings.NATIVE_FUNCTION_NAMES)
            domain_functions=[name for name in bindings.FUNCTION_NAMES if name not in bindings.NATIVE_FUNCTION_NAMES]
            assert domain_functions
            fails(bindings.CodecError,'UnsupportedFunction',lambda:client.call(domain_functions[0]))
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
        for options in ({'max_nodes':100001},{'max_depth':129},{'max_steps':0},{'max_frames':True}):
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
        assert bindings.CALLS['main::change'](client,pair)==expected[1]
    print('Python native bindings: typed VM/native agreement, full-width scalars, snapshots, variants/tables, traps, budgets, no-retry capacity errors, schema mismatch and source-independent calls passed')


if __name__=='__main__':
    main()
