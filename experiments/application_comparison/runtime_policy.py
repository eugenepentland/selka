"""Coordinator-owned system mount policy shared by execution and receipts.

Use explicit distribution paths. Locally installed /usr/local software is not
part of the participant runtime. Additional tools require named, pinned mounts.
This is a mutable-host policy, not a hermetic or immutable runtime image.
"""
SYSTEM_PATHS = ('/usr/bin', '/usr/sbin', '/usr/lib', '/usr/lib64', '/usr/libexec',
                '/usr/share/locale', '/usr/share/zoneinfo', '/usr/share/terminfo',
                '/usr/share/git-core', '/usr/include', '/bin', '/lib', '/lib64',
                # Debian's /usr/bin/cc is an absolute symlink through this entry;
                # Rust's default linker discovery needs the target inside the chroot.
                '/etc/alternatives', '/etc/ld.so.cache', '/etc/localtime')
