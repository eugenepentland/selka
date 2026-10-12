#!/usr/bin/env bash
# Reconstruct the unchanged modern-syntax comparison control.
set -euo pipefail
output=${1:?pass an empty destination directory}
script_dir=$(cd "$(dirname "$0")" && pwd)
if [[ -e "$output" ]]; then
    echo "refusing to overwrite $output" >&2
    exit 2
fi
mkdir -p "$output"
tar -xzf "$script_dir/original.tar.gz" -C "$output"
(cd "$output" && gzip -dc "$script_dir/evidence/syntax-migration.patch.gz" | patch --batch --fuzz=0 -p4)
(cd "$output" && sha256sum -c "$script_dir/evidence/modern-syntax-sha256.txt")
