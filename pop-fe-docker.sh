#!/bin/bash
#
# Run pop-fe from its Docker image (see Dockerfile) with input and output
# directories mounted into the container. Works on linux/amd64 and
# linux/arm64 hosts, e.g. a Synology NAS or a Mac with Docker Desktop.
#
# Directories are mounted at the same path inside the container, so all
# paths given to pop-fe stay the same as on the host. Input directories are
# mounted read-only.
#
# Usage:
#   pop-fe-docker.sh -i <input dir> [-i <input dir> ...] -o <output dir>
#                    [-w <work dir>] [-I <image>] [-u] [--] [pop-fe arguments]
#
#   -u  pull the latest image before running
#   The image defaults to ghcr.io/hosterholz/pop-fe:latest and can also be
#   set with the POPFE_IMAGE environment variable.
#
# Without an explicit target option (--psp-dir, --ps3-pkg, ...) the game is
# built as a PSP EBOOT into the output directory (--psp-dir=<output dir>).
#
# Example:
#   pop-fe-docker.sh -i /volume1/games/psx -o /volume1/games/psp -- \
#       "/volume1/games/psx/Xenogears/Xenogears (USA) (Disc 1).cue" \
#       "/volume1/games/psx/Xenogears/Xenogears (USA) (Disc 2).cue"

set -euo pipefail

# Non-interactive SSH sessions (Synology) and some Mac shells lack the
# directory docker is installed in.
PATH=$PATH:/usr/local/bin:/opt/homebrew/bin
command -v docker >/dev/null || { echo "docker not found." >&2; exit 1; }

image=${POPFE_IMAGE:-ghcr.io/hosterholz/pop-fe:latest}
pull=no
output=
workdir=
mounts=()

usage() {
    sed -n '3,/^$/s/^# \{0,1\}//p' "$0"
    exit "${1:-1}"
}

abspath() {
    (cd "$1" && pwd -P)
}

while getopts "i:o:w:I:uh" opt; do
    case $opt in
        i) [[ -d $OPTARG ]] || { echo "Input directory not found: $OPTARG" >&2; exit 1; }
           d=$(abspath "$OPTARG")
           mounts+=(--mount "type=bind,source=$d,target=$d,readonly") ;;
        o) mkdir -p "$OPTARG"
           output=$(abspath "$OPTARG") ;;
        w) mkdir -p "$OPTARG"
           workdir=$(abspath "$OPTARG") ;;
        I) image=$OPTARG ;;
        u) pull=yes ;;
        h) usage 0 ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

[[ -n $output ]] || { echo "An output directory (-o) is required." >&2; usage; }
(( ${#mounts[@]} )) || echo "Warning: no input directory (-i) mounted." >&2

mounts+=(--mount "type=bind,source=$output,target=$output")

# pop-fe's temporary files (several GB for multi-disc games) go to the
# container layer, which --rm discards, unless a work directory is given.
if [[ -n $workdir ]]; then
    mounts+=(--mount "type=bind,source=$workdir,target=/pop-fe/pop-fe-work")
fi

have_target=no
for a in "$@"; do
    case $a in
        --psp-dir*|--ps3-pkg*|--psio-dir*|--ps2-dir*|--psc-dir*|--retroarch-*) have_target=yes ;;
    esac
done
if [[ $have_target == no ]]; then
    set -- "--psp-dir=$output" "$@"
fi

if [[ $pull == yes ]]; then
    docker pull "$image"
fi

exec docker run --rm --init \
    --user "$(id -u):$(id -g)" \
    "${mounts[@]}" \
    "$image" "$@"
