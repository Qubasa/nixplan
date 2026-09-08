#!/usr/bin/env bash
# Measure what it costs to evaluate the planner over each performance fixture.
# The measurement evaluates and deeply forces a plan; it builds nothing, it
# realises nothing and it needs no network.
set -euo pipefail

# The $names in both filters are jq variables bound with --arg, not shell ones.
# shellcheck disable=SC2016
readonly RUN_FILTER='{
	cpuTime: .cpuTime,
	wallClock: $wall,
	counters: {
		nrThunks: .nrThunks,
		nrFunctionCalls: .nrFunctionCalls,
		nrPrimOpCalls: .nrPrimOpCalls,
		"values.number": .values.number,
		"sets.bytes": .sets.bytes,
		"envs.bytes": .envs.bytes,
		"list.elements": .list.elements,
		nrOpUpdateValuesCopied: .nrOpUpdateValuesCopied,
		"gc.totalBytes": .gc.totalBytes
	}
}'

# shellcheck disable=SC2016
readonly RESULT_FILTER='{
	fixture: $fixture,
	size: $size,
	interpreter: $interpreter,
	entries: $entries,
	runs: .
}'

korora=""
nixpkgs=""
out=""
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repeats=2
fixtures="worked,fleet,mesh"
sizes="4,16,64,256"
interpreter=""
tmpdir=""
lib=""
folder=""
worked=""

usage() {
	cat <<'EOF'
Usage: measure.sh --korora <store path> --nixpkgs <store path> --out <dir> [options]

  --korora <path>    store path of the korora library the fixtures evaluate against
  --nixpkgs <path>   store path of the nixpkgs whose lib.systems the planner elaborates with
  --out <dir>        directory the per-fixture result files are written to
  --root <dir>       directory holding eval.nix (default: this script's directory)
  --lib <dir>        the planner library eval.nix imports (default: <root>/../lib)
  --folder <dir>     fixtures/minimal-typed-edge (default: relative to <root>)
  --worked <file>    the loader turning that folder into planner arguments
                     (default: <root>/../tests/unit/worked.nix)
  --repeats <n>      measured evaluations per fixture and size (default: 2)
  --fixtures <list>  comma-separated fixture names (default: worked,fleet,mesh)
  --sizes <list>     comma-separated fleet sizes, for the sized fixtures (default: 4,16,64,256)
EOF
}

die() {
	printf 'measure.sh: %s\n' "$1" >&2
	exit 1
}

set_option() {
	case "$1" in
	--korora) korora="$2" ;;
	--nixpkgs) nixpkgs="$2" ;;
	--out) out="$2" ;;
	--root) root="$2" ;;
	--lib) lib="$2" ;;
	--folder) folder="$2" ;;
	--worked) worked="$2" ;;
	--repeats) repeats="$2" ;;
	--fixtures) fixtures="$2" ;;
	--sizes) sizes="$2" ;;
	esac
}

parse_args() {
	while [ $# -gt 0 ]; do
		case "$1" in
		--korora | --nixpkgs | --out | --root | --lib | --folder | --worked | --repeats | --fixtures | --sizes)
			[ $# -ge 2 ] || die "$1 needs a value"
			set_option "$1" "$2"
			shift 2
			;;
		-h | --help)
			usage
			exit 0
			;;
		*) die "unknown argument: $1" ;;
		esac
	done
}

check_args() {
	[ -n "$korora" ] || die "--korora is required"
	[ -n "$nixpkgs" ] || die "--nixpkgs is required"
	[ -n "$out" ] || die "--out is required"
	[ -f "$root/eval.nix" ] || die "no eval.nix under --root $root"
	[ -n "$lib" ] || lib="$root/../lib"
	[ -n "$folder" ] || folder="$root/../fixtures/minimal-typed-edge"
	[ -n "$worked" ] || worked="$root/../tests/unit/worked.nix"
	[ -d "$lib" ] || die "no planner library at --lib $lib"
	[ -d "$folder" ] || die "no worked deployment at --folder $folder"
	[ -f "$worked" ] || die "no worked loader at --worked $worked"
	case "$repeats" in
	'' | *[!0-9]*) die "--repeats takes a positive integer, got $repeats" ;;
	esac
	[ "$repeats" -ge 1 ] || die "--repeats takes a positive integer, got $repeats"
	command -v jq >/dev/null || die "jq is required"
}

nix_version() {
	local reported
	reported="$(nix --version)"
	printf '%s\n' "${reported##* }"
}

elapsed() {
	jq -n --arg from "$1" --arg to "$2" \
		'(($to | tonumber) - ($from | tonumber)) * 1000 | round / 1000'
}

# Runs one measured evaluation, writes its run record under $tmpdir and prints
# the plan entry count the evaluation reported.
measure_run() {
	local fixture="$1" size="$2" label="$3" index="$4"
	local prefix="$tmpdir/$label.$index"
	local started ended wall printed entries apply

	# `nix eval --file` does not auto-call a function from --argstr, so the
	# arguments are applied explicitly.
	apply="$(printf 'f: f { korora = "%s"; nixpkgs = "%s"; fixture = "%s"; size = "%s"; lib = "%s"; folder = "%s"; worked = "%s"; }' \
		"$korora" "$nixpkgs" "$fixture" "$size" "$lib" "$folder" "$worked")"

	started="$(date +%s.%N)"
	if ! NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="$prefix.stats.json" \
		nix eval --raw --no-eval-cache --file "$root/eval.nix" \
		--apply "$apply" >"$prefix.out" 2>"$prefix.err"; then
		cat "$prefix.err" >&2
		die "the evaluation of $label failed; its stderr is above"
	fi
	ended="$(date +%s.%N)"

	printed="$(cat "$prefix.out")"
	case "$printed" in
	*entries=*) ;;
	*) die "the evaluation of $label printed no entries= count: $printed" ;;
	esac
	entries="${printed#*entries=}"
	entries="${entries%%[!0-9]*}"
	[ -n "$entries" ] || die "the entries= count of $label is not a number: $printed"
	[ -s "$prefix.stats.json" ] || die "nix wrote no statistics for $label"

	wall="$(elapsed "$started" "$ended")"
	jq --argjson wall "$wall" "$RUN_FILTER" "$prefix.stats.json" >"$prefix.run.json"
	printf '%s\n' "$entries"
}

measure_case() {
	local fixture="$1" size="$2" label="$3" size_json="$4"
	local index entries first=""
	local runs=()

	for ((index = 1; index <= repeats; index++)); do
		entries="$(measure_run "$fixture" "$size" "$label" "$index")"
		if [ -z "$first" ]; then
			first="$entries"
		elif [ "$entries" != "$first" ]; then
			die "$label produced $first plan entries and then $entries; the fixture is not deterministic"
		fi
		runs+=("$tmpdir/$label.$index.run.json")
	done

	jq -s --arg fixture "$fixture" --argjson size "$size_json" \
		--arg interpreter "$interpreter" --argjson entries "$first" \
		"$RESULT_FILTER" "${runs[@]}" >"$out/$label.json"
	printf 'measure.sh: wrote %s (%s runs, %s plan entries)\n' \
		"$out/$label.json" "$repeats" "$first"
}

measure_fixture() {
	local fixture="$1" size
	local size_list=()

	case "$fixture" in
	worked) measure_case worked 0 worked null ;;
	fleet | mesh)
		IFS=',' read -r -a size_list <<<"$sizes"
		for size in "${size_list[@]}"; do
			case "$size" in
			'' | *[!0-9]*) die "--sizes takes comma-separated integers, got $sizes" ;;
			esac
			measure_case "$fixture" "$size" "$fixture-$size" "$size"
		done
		;;
	*) die "unknown fixture: $fixture" ;;
	esac
}

main() {
	local fixture
	local fixture_list=()

	parse_args "$@"
	check_args
	mkdir -p "$out"
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "$tmpdir"' EXIT
	interpreter="$(nix_version)"
	printf 'measure.sh: nix %s, %s repeats per case\n' "$interpreter" "$repeats"

	IFS=',' read -r -a fixture_list <<<"$fixtures"
	for fixture in "${fixture_list[@]}"; do
		measure_fixture "$fixture"
	done
}

main "$@"
