"""Trusted single-request HTTP worker. Never exposed as a participant tool."""
import ctypes
import http.client
import os
import sys
from urllib.parse import urlsplit


def main():
    # Terminate the network worker if its coordinator dies during an API request.
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(1, 9, 0, 0, 0) != 0 or os.getppid() != int(sys.argv[1]):
        return 125
    key = os.environ['OPENAI_API_KEY']
    endpoint = urlsplit(os.environ['COMPARISON_MODEL_ENDPOINT'])
    if endpoint.username or endpoint.password or endpoint.fragment or endpoint.query:
        raise ValueError('invalid model endpoint')
    local_fixture = endpoint.scheme == 'http' and endpoint.hostname == '127.0.0.1' and key == 'fixture'
    official = endpoint.scheme == 'https' and endpoint.hostname == 'api.openai.com' and endpoint.port in (None, 443)
    if not (official or local_fixture) or endpoint.path != '/v1/responses':
        raise ValueError('unsupported model endpoint')
    request = sys.stdin.buffer.read(64 * 1024 * 1024 + 1)
    if len(request) > 64 * 1024 * 1024:
        raise ValueError('request too large')
    connection_type = http.client.HTTPConnection if local_fixture else http.client.HTTPSConnection
    connection = connection_type(endpoint.hostname, endpoint.port, timeout=60)
    try:
        connection.request('POST', endpoint.path, body=request,
                           headers={'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json'})
        response = connection.getresponse()
        # No redirects, automatic retries, or unaudited authentication discovery.
        if response.status != 200:
            sys.stderr.write('model HTTP status ' + str(response.status))
            return 1
        body = response.read(32 * 1024 * 1024 + 1)
        if len(body) > 32 * 1024 * 1024:
            raise ValueError('response too large')
        sys.stdout.buffer.write(body)
    finally:
        connection.close()
    return 0


if __name__ == '__main__':
    try:
        result = main()
    except Exception as error:
        # Do not log exception messages that could contain authentication material.
        sys.stderr.write('model transport failure: ' + type(error).__name__)
        result = 1
    raise SystemExit(result)
