"""Coordinator-owned system mount policy shared by execution and receipts.

Use explicit distribution paths. Locally installed /usr/local software is not
part of the participant runtime. Additional tools require named, pinned mounts.
This is a mutable-host policy, not a hermetic or immutable runtime image.
"""
SYSTEM_PATHS = ('/usr/bin', '/usr/sbin', '/usr/lib', '/usr/lib64',
                '/usr/share/locale', '/usr/share/zoneinfo', '/usr/share/terminfo',
                '/usr/share/git-core', '/usr/include', '/bin', '/lib', '/lib64',
                '/etc/ld.so.cache', '/etc/localtime')
