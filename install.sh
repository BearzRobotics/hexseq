#!/usr/bin/sh
set -e

PREFIX="/usr"
BINDIR="$PREFIX/bin"
DOCDIR="$PREFIX/share/doc/hexseq"

BINFILE="zig-out/bin/hexseq"
DOCFILE="docs/hexseq.md"

usage() {
    echo "Usage: sudo $0 {install|uninstall}"
    exit 1
}

[ $# -eq 1 ] || usage

case "$1" in
    install)
        echo "Installing hexseq..."

        install -Dm755 "$BINFILE" "$BINDIR/hexseq"
        install -Dm644 "$DOCFILE" "$DOCDIR/hexseq.md"

        echo "Done."
        ;;

    uninstall)
        echo "Uninstalling hexseq..."

        rm -f "$BINDIR/hexseq"
        rm -f "$DOCDIR/hexseq.md"

        # Remove empty doc directory if unused
        rmdir "$DOCDIR" 2>/dev/null || true

        echo "Done."
        ;;

    *)
        usage
        ;;
esac
