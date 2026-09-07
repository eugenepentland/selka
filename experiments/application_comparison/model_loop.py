"""Explicit participant tool loop; transport is injected by the trusted coordinator.

No hosted tools are enabled. A production transport must enforce the supplied
wall timeout itself; this loop additionally rejects late responses before dispatch.
Fixture transports test routing and do not establish live-model access or usage.
"""
import copy
import subprocess
from . import session
from .execution import parse_output
from .storage import canonical, digest, locked, write_json


def tool_definitions(preparation=False):
    definitions = []
    for name, description, properties in [
        ('command', 'Run argv inside the participant workspace; use shell/editor commands to inspect and edit files.',
         {'argv': {'type': 'array', 'items': {'type': 'string'}}}),
        ('check', 'Capture current source and run the public verification suite.', {}),
        ('finish', ('Finish checked practice and begin the task, or record unsuccessful practice.' if preparation
                    else 'Stop the task after checking final edits, or abandon the attempt.'),
         {'reason': {'type': 'string', 'enum': ['completed', 'abandoned']}}),
    ]:
        definitions.append({'type': 'function', 'name': name, 'description': description, 'strict': True,
                            'parameters': {'type': 'object', 'properties': properties,
                                           'required': list(properties), 'additionalProperties': False}})
    return definitions


def run_task(gateway, complete, *, model, prompt, transport_identity, history=(), max_turns=100,
             max_output_tokens=4096, max_reported_tokens=None, _preparation=False):
    """Run one active task. `complete(body, timeout=seconds)` returns a JSON object.

History is coordinator-supplied participant practice history, never another run.
Every request, response and tool result stays outside candidate mounts. Incomplete
runs are retained and cannot be silently restarted over their prior directory.
"""
    manifest = session.load(gateway.root)
    if 'max_reported_tokens_per_phase' in manifest and max_reported_tokens != manifest['max_reported_tokens_per_phase']:
        raise ValueError('reported token limit differs from frozen session')
    active_phase = 'preparing' if _preparation else 'working'
    if manifest['phase'] != active_phase or manifest['model'] != model:
        raise ValueError('model loop requires matching active task')
    if (type(max_turns) is not int or max_turns <= 0 or type(max_output_tokens) is not int or
            max_output_tokens <= 0 or not isinstance(prompt, str) or not transport_identity):
        raise ValueError('invalid model loop configuration')
    if max_reported_tokens is not None and (type(max_reported_tokens) is not int or max_reported_tokens <= 0):
        raise ValueError('reported token limit must be a positive integer')
    transcript = copy.deepcopy(list(history)) + [{'role': 'user', 'content': prompt}]
    directory = gateway.root / ('model-preparation' if _preparation else 'model-task')
    directory.mkdir(exist_ok=False)
    config = {'model': model, 'transport': transport_identity, 'max_turns': max_turns,
              'max_output_tokens': max_output_tokens, 'max_reported_tokens': max_reported_tokens, 'initial_input': copy.deepcopy(transcript),
              'tools': tool_definitions(_preparation), 'record_kind': manifest['record_kind'], 'phase': active_phase}
    write_json(directory / 'configuration.json', config)
    started = manifest['preparation_started' if _preparation else 'task_started']
    budget = manifest['budgets']['preparation_seconds' if _preparation else 'task_seconds']
    totals = {'input_tokens': 0, 'output_tokens': 0, 'total_tokens': 0}
    usage_complete = True
    seen = set()
    response_ids = []
    stop = 'turn-limit'
    def remaining():
        return budget - session.elapsed(started, session.clock())
    with locked(directory):
        try:
            for turn in range(max_turns):
                if remaining() <= 0:
                    stop = 'budget'
                    break
                turn_dir = directory / f'{turn:04}'
                turn_dir.mkdir()
                body = {'model': model, 'input': copy.deepcopy(transcript), 'tools': tool_definitions(_preparation),
                        'parallel_tool_calls': False, 'store': False, 'max_output_tokens': max_output_tokens,
                        'include': ['reasoning.encrypted_content']}
                write_json(turn_dir / 'request.json', body)
                try:
                    response = complete(body, timeout=remaining())
                except (TimeoutError, subprocess.TimeoutExpired):
                    usage_complete = False
                    stop = 'budget' if remaining() <= 0 else 'transport-timeout'
                    write_json(turn_dir / 'transport-timeout.json', {'at': session.clock(), 'usage_known': False})
                    break
                write_json(turn_dir / 'response.json', response)
                if not isinstance(response, dict) or response.get('model') != model:
                    raise ValueError('unexpected model response identity')
                response_ids.append(response.get('id'))
                usage = response.get('usage')
                if (not isinstance(usage, dict) or any(type(usage.get(key)) is not int or usage[key] < 0 for key in totals) or
                        usage['input_tokens'] + usage['output_tokens'] != usage['total_tokens']):
                    usage_complete = False
                else:
                    for key in totals:
                        totals[key] += usage[key]
                if max_reported_tokens is not None and (not usage_complete or totals['total_tokens'] >= max_reported_tokens):
                    stop = 'usage-unknown' if not usage_complete else 'reported-token-limit'
                    break
                if remaining() <= 0:
                    stop = 'budget'
                    break
                if response.get('status') != 'completed' or not isinstance(response.get('output'), list):
                    stop = 'incomplete-model-response'
                    break
                output = response['output']
                calls = []
                for item in output:
                    if not isinstance(item, dict) or item.get('type') not in ('message', 'reasoning', 'function_call'):
                        raise ValueError('undeclared model output/tool type')
                    if item['type'] == 'function_call':
                        call_id = item.get('call_id')
                        if not isinstance(call_id, str) or not call_id or call_id in seen:
                            raise ValueError('duplicate or invalid tool call identity')
                        seen.add(call_id)
                        if item.get('name') not in ('command', 'check', 'finish') or not isinstance(item.get('arguments'), str):
                            raise ValueError('undeclared tool or invalid arguments')
                        calls.append(item)
                if len(calls) > 1:
                    raise ValueError('parallel tool calls are disabled')
                # Reasoning items must accompany tool outputs on continuation.
                transcript.extend(copy.deepcopy(output))
                if not calls:
                    stop = 'model-ended-without-finish'
                    break
                call = calls[0]
                try:
                    arguments = parse_output(call['arguments'].encode('utf-8'))
                    result = gateway.dispatch(call['name'], arguments)
                except ValueError as error:
                    result = {'error': str(error)}
                write_json(turn_dir / 'tool-result.json', result)
                transcript.append({'type': 'function_call_output', 'call_id': call['call_id'],
                                   'output': canonical(result).decode('utf-8')})
                if session.load(gateway.root)['phase'] != active_phase:
                    stop = 'preparation-ended' if _preparation else 'sealed'
                    break
        except Exception as error:
            write_json(directory / 'failure.json', {'type': type(error).__name__, 'message': str(error)})
            raise
        finally:
            write_json(directory / 'transcript.json', transcript)
        if session.load(gateway.root)['phase'] == active_phase:
            if _preparation:
                if stop == 'reported-token-limit':
                    session.start_task(gateway.root, 'budget')
                else:
                    gateway.dispatch('finish', {'reason': 'abandoned'})
            else:
                session.seal(gateway.root, 'budget' if remaining() <= 0 or stop == 'reported-token-limit' else 'abandoned')
        report = {'version': 'participant-model-loop-v1', 'record_kind': manifest['record_kind'],
                  'configuration_sha256': digest(config), 'stop': stop, 'response_ids': response_ids,
                  'reported_usage': totals, 'usage_complete': usage_complete,
                  'reported_token_limit': max_reported_tokens,
                  'reported_token_overshoot': max(0, totals['total_tokens'] - max_reported_tokens) if max_reported_tokens is not None and usage_complete else None,
                  'hard_billing_cap': False, 'comparative_claim': False}
        write_json(directory / 'result.json', report)
        return report


def run_preparation(gateway, complete, **settings):
    return run_task(gateway, complete, _preparation=True, **settings)
