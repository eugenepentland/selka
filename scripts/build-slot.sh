#!/usr/bin/env bash
# Thin client. Default shadow records scheduler decisions while preserving the
# existing admission policy. SELKA_ADMISSION_BACKEND=scheduler is qualification
# opt-in until an actual day of shared traffic has been reviewed.

# The request starts here: the wait the wrapper reports (`build-slot: ... after Ns`, SELKA_ADMISSION_WAIT_S) counts
# the interpreter's start and the shadow observer's registration too, not only the queue. A shell variable, no process.
export SELKA_ADMISSION_STARTED_US=${EPOCHREALTIME/[.,]/}

# Watch mode needs a stable identity pathname across Maker updates. Only this
# checkout's explicit capability declaration authorizes adding the option;
# older trees, arbitrary projects, shell commands, and overrides pass unchanged.
normalize_watch_identity() {
    local -n admission_args=$1
    local command_index=1 index insert watch=0 marker=0 imported=0 line
    case ${admission_args[0]:-} in build|gate|timing) ;; *) return ;; esac
    [[ ${admission_args[command_index]:-} == -- ]] && ((command_index += 1))
    [[ ${admission_args[command_index]:-} == zig || ${admission_args[command_index]:-} == */zig ]] || return
    [[ ${admission_args[command_index + 1]:-} == build ]] || return
    insert=$((command_index + 2))
    for ((index=insert; index<${#admission_args[@]}; index++)); do
        case ${admission_args[index]} in
            --) break ;;
            --build-file|--build-file=*|-Dwatch-identity*) return ;;
            --watch) watch=1 ;;
        esac
    done
    [[ $watch == 1 && -f build.zig && -r build.zig && -f build_identity.zig && -r build_identity.zig ]] || return
    while IFS= read -r line || [[ -n $line ]]; do
        [[ $line == 'pub const admission_watch_identity = true;' ]] && marker=1
    done < build_identity.zig
    [[ $marker == 1 ]] || return
    while IFS= read -r line || [[ -n $line ]]; do
        if [[ $line =~ ^[[:space:]]*const\ identity\ =\ @import\(\"build_identity.zig\"\)\.module\( ]]; then
            imported=1
        fi
    done < build.zig
    [[ $imported == 1 ]] || return
    admission_args=("${admission_args[@]:0:insert}" -Dwatch-identity=true "${admission_args[@]:insert}")
}

forward=("$@")
normalize_watch_identity forward
exec python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/build_admission.py" "${forward[@]}"
