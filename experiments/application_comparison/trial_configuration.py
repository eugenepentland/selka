"""Concrete stdlib-only execution configurations; constructing one never launches a model."""
from pathlib import Path
from . import environment_receipt, guardian_adapter
from .execution import freeze_adapter, verify_adapter
from .isolation import Limits
from .storage import digest


def command_plan(language, application, arm, *, practice=False):
    if language == 'python':
        name = 'main.py' if practice else ('planner.py' if application == 'planner' else 'inspector.py')
        return [dict(phase='run', argv=['/usr/bin/python3', '-S', '-B', name])]
    if language == 'my':
        return [dict(phase='run', argv=['/tools/byte_io', '--project', '/work'])]
    commands = guardian_adapter.commands()
    return commands[2:] if practice else (commands if arm == 'main' else commands[1:])


def freeze(language, application, arm, *, zig=None, guardian=None, byte_io=None, compiler=None, navigate=None, workflow=None):
    if language not in ('my', 'python', 'zig') or application not in ('planner', 'eda') or arm not in ('main', 'language-focused'):
        raise ValueError('invalid trial condition')
    if workflow is not None and (language != 'my' or arm != 'main' or not Path(workflow).is_dir()):
        raise ValueError('workflow directory requires the main my arm')
    limits = Limits(wall_seconds=60, cpu_seconds=60, memory_bytes=4 * 1024**3)
    tools = {}
    if language == 'python':
        task = freeze_adapter(language, {}, command_plan(language, application, arm), limits)
        practice = freeze_adapter(language, {}, command_plan(language, application, arm, practice=True), limits)
    elif language == 'my':
        if byte_io is None:
            raise ValueError('installed bytecode host required')
        tools = {'byte_io': str(Path(byte_io).resolve(strict=True))}
        if arm == 'main':
            if compiler is None or navigate is None:
                raise ValueError('main my arm requires installed compiler and navigation client')
            tools.update(compiler=str(Path(compiler).resolve(strict=True)), navigate=str(Path(navigate).resolve(strict=True)))
        if workflow is not None:
            tools['workflow'] = str(Path(workflow).resolve(strict=True))
        task = freeze_adapter(language, tools, command_plan(language, application, arm), limits)
        practice = task
    else:
        if zig is None or not (Path(zig) / 'zig').is_file() or not (Path(zig) / 'lib').is_dir():
            raise ValueError('complete Zig toolchain directory required')
        tools = {'zig': str(Path(zig).resolve(strict=True))}
        practice = freeze_adapter(language, tools, command_plan(language, application, arm, practice=True), limits)
        if arm == 'main':
            if guardian is None:
                raise ValueError('Guardian executable required for main Zig arm')
            task = guardian_adapter.freeze(guardian, tools['zig'])
        else:
            task = freeze_adapter(language, tools, command_plan(language, application, arm), limits)
    environment = environment_receipt.capture(tools=environment_receipt.session_tools(tools, task, practice))
    body = {'version': 'application-trial-configuration-v3' if workflow is not None else 'application-trial-configuration-v2', 'language': language,
            'application': application, 'arm': arm, 'tools': tools,
            'task_adapter': task, 'practice_adapter': practice, 'environment': environment,
            'scored_launch_authorized': False}
    return dict(body, sha256=digest(body))


def validate(configuration):
    fields = {'version', 'language', 'application', 'arm', 'tools', 'task_adapter',
              'practice_adapter', 'environment', 'scored_launch_authorized', 'sha256'}
    if not isinstance(configuration, dict) or set(configuration) != fields:
        raise ValueError('invalid trial configuration fields')
    body = {key: value for key, value in configuration.items() if key != 'sha256'}
    if configuration.get('version') not in ('application-trial-configuration-v1', 'application-trial-configuration-v2', 'application-trial-configuration-v3') or digest(body) != configuration.get('sha256'):
        raise ValueError('trial configuration changed')
    if configuration['scored_launch_authorized'] is not False:
        raise ValueError('configuration does not authorize scored launch')
    language, application, arm = (configuration[key] for key in ('language', 'application', 'arm'))
    if language not in ('my', 'python', 'zig') or application not in ('planner', 'eda') or arm not in ('main', 'language-focused'):
        raise ValueError('invalid trial condition')
    tool_names = {'python': set(), 'my': {'byte_io'}, 'zig': {'zig'}}[language]
    if configuration['version'] in ('application-trial-configuration-v2', 'application-trial-configuration-v3') and language == 'my' and arm == 'main':
        tool_names |= {'compiler', 'navigate'}
    if configuration['version'] == 'application-trial-configuration-v3':
        if language != 'my' or arm != 'main':
            raise ValueError('workflow configuration requires main my arm')
        tool_names.add('workflow')
    if not isinstance(configuration['tools'], dict) or set(configuration['tools']) != tool_names:
        raise ValueError('participant tool inventory mismatch')
    for practice, adapter in ((False, configuration['task_adapter']), (True, configuration['practice_adapter'])):
        expected_tools = tool_names | ({'guardian', 'guardian_runner', 'guardian_policy'}
                                      if language == 'zig' and arm == 'main' and not practice else set())
        if (adapter['language'] != language or adapter['commands'] != command_plan(language, application, arm, practice=practice) or
                adapter['limits'] != Limits(wall_seconds=60, cpu_seconds=60, memory_bytes=4 * 1024**3).__dict__ or
                set(adapter['tools']) != expected_tools or
                any(adapter['tools'][name]['path'] != path for name, path in configuration['tools'].items()) or
                digest({key: value for key, value in adapter.items() if key != 'sha256'}) != adapter['sha256']):
            raise ValueError('trial adapter does not match its condition')
    environment_receipt.validate(configuration['environment'], require_system=True,
        required_tools=environment_receipt.session_tools(configuration['tools'],
            configuration['task_adapter'], configuration['practice_adapter']))


def verify(configuration):
    validate(configuration)
    for adapter in (configuration['task_adapter'], configuration['practice_adapter']):
        verify_adapter(adapter)
    if configuration['language'] == 'zig' and configuration['arm'] == 'main':
        guardian_adapter.require(configuration['task_adapter'])
    return environment_receipt.verify(configuration['environment'], require_system=True,
        required_tools=environment_receipt.session_tools(configuration['tools'],
            configuration['task_adapter'], configuration['practice_adapter']))
