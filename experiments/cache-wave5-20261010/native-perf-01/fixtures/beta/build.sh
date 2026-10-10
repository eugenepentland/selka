#!/bin/sh
set -eu
compiler=$1
linker=$2
project=$3
binary=$4
provider=$5
"$compiler" --64 -I "$provider" "$project/work.S" -o "$project/work.o"
"$linker" -m elf_x86_64 -nostdlib --no-dynamic-linker --build-id=none -o "$binary" "$project/work.o"
