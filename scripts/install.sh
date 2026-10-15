#!/bin/bash
# Local compatibility entry. The standalone server entry is /sh.
exec /bin/bash "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install-unix.sh" "$@"
