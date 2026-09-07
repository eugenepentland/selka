"""Bounded OpenAI Responses transport, with credentials kept outside model tools."""
import os
from pathlib import Path
import signal
import subprocess
import sys
from .execution import parse_output
from .storage import canonical, digest, path_identity


class ResponsesTransport:
    def __init__(self, api_key, *, endpoint='https://api.openai.com/v1/responses'):
        if not isinstance(api_key, str) or not api_key or '\n' in api_key or '\r' in api_key:
            raise ValueError('configure an API key locally before live model execution')
        self._api_key = api_key
        self.endpoint = endpoint
        self.worker = Path(__file__).with_name('responses_worker.py').resolve()
        self.identity = self.current_identity()

    def current_identity(self):
        return digest({'endpoint': self.endpoint, 'worker': path_identity(self.worker),
                       'python': path_identity(sys.executable)})

    def __call__(self, body, *, timeout):
        if self.current_identity() != self.identity:
            raise ValueError('model transport configuration changed')
        if timeout <= 0:
            raise TimeoutError('model request has no remaining time')
        encoded = canonical(body)
        if len(encoded) > 64 * 1024 * 1024:
            raise ValueError('model request exceeds transport limit')
        environment = {'OPENAI_API_KEY': self._api_key, 'COMPARISON_MODEL_ENDPOINT': self.endpoint,
                       'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8'}
        worker = subprocess.Popen([sys.executable, '-I', '-S', str(self.worker), str(os.getpid())],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  env=environment, start_new_session=True)
        try:
            stdout, stderr = worker.communicate(encoded, timeout=timeout)
        except BaseException:
            try:
                os.killpg(worker.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            worker.communicate()
            raise
        if worker.returncode != 0:
            raise RuntimeError(stderr.decode('utf-8', errors='replace')[:1024] or 'model transport failed')
        result = parse_output(stdout)
        if not isinstance(result, dict):
            raise ValueError('model response must be an object')
        return result
