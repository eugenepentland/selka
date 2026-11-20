#!/bin/sh
# Install the Selka release in this folder into ${PREFIX:-$HOME/.local}:
#
#   bin/selka            the compiler (and bin/selka.commit, the commit it was built at)
#   libexec/selka/       its two helper programs (components)
#   lib/selka/zig/       the Zig it drives, with Zig's own LICENSE
#
# An earlier install of the same layout is replaced; nothing else under PREFIX is touched.
# usage: ./install.sh            (into $HOME/.local)
#        PREFIX=/opt/selka ./install.sh
set -eu

if [ "$(uname -s)" != Linux ] || [ "$(uname -m)" != x86_64 ]; then
    echo "install.sh: this release is for Linux on x86-64; this machine is $(uname -s) $(uname -m)" >&2
    exit 1
fi

here=$(cd "$(dirname "$0")" && pwd)
for needed in bin/selka libexec/selka/components lib/selka/zig/zig lib/selka/zig/lib; do
    if [ ! -e "$here/$needed" ]; then
        echo "install.sh: $here/$needed is missing: run install.sh from the unpacked release folder" >&2
        exit 1
    fi
done

if [ -z "${PREFIX:-}" ] && [ -z "${HOME:-}" ]; then
    echo "install.sh: neither PREFIX nor HOME is set; say where to install: PREFIX=DIR ./install.sh" >&2
    exit 1
fi
prefix=${PREFIX:-$HOME/.local}
case $prefix in
    /*) ;;
    *) prefix=$(pwd)/$prefix ;;
esac

mkdir -p "$prefix/bin" "$prefix/libexec" "$prefix/lib"

# Copy beside the destination first and move into place, so an interrupted copy leaves the old install whole.
stage=$prefix/.selka-install.$$
trap 'rm -rf "$stage"' EXIT
rm -rf "$stage"
mkdir -p "$stage"
cp -R "$here/libexec/selka" "$stage/libexec"
cp -R "$here/lib/selka" "$stage/lib"
cp "$here/bin/selka" "$stage/selka"
if [ -f "$here/bin/selka.commit" ]; then cp "$here/bin/selka.commit" "$stage/selka.commit"; fi

rm -rf "$prefix/libexec/selka" "$prefix/lib/selka"
rm -f "$prefix/bin/selka" "$prefix/bin/selka.commit"
mv "$stage/libexec" "$prefix/libexec/selka"
mv "$stage/lib" "$prefix/lib/selka"
mv "$stage/selka" "$prefix/bin/selka"
if [ -f "$stage/selka.commit" ]; then mv "$stage/selka.commit" "$prefix/bin/selka.commit"; fi

echo "Installed Selka into $prefix:"
echo "  $prefix/bin/selka"
echo "  $prefix/libexec/selka/"
echo "  $prefix/lib/selka/   (the Zig it uses is $prefix/lib/selka/zig/zig)"
case ":${PATH:-}:" in
    *":$prefix/bin:"*) ;;
    *)
        echo
        echo "$prefix/bin is not on your PATH. Add it (for example in ~/.profile):"
        echo "  export PATH=\"$prefix/bin:\$PATH\""
        ;;
esac
echo
echo "Try:  selka --version"
echo "To uninstall, remove:"
echo "  $prefix/bin/selka (and $prefix/bin/selka.commit)"
echo "  $prefix/libexec/selka"
echo "  $prefix/lib/selka"
