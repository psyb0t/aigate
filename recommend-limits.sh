#!/usr/bin/env bash
# Checks the enabled service set against this machine and writes .env.limits.
#
# Every service's memory and CPU limit is a fixed number: the default in
# docker-compose.yml (`${NAME_MEM_LIMIT:-12g}` and friends), overridable per
# service in .env. A model needs the same RAM on a 16 GB host as on a 256 GB
# host, so limits are never derived from a share of the host.
#
# This script does two things with those numbers:
#
#   1. Caps CPU limits at the host core count. Docker refuses a `cpus` value
#      above the number of cores, so on a small host the compose default would
#      stop the container from starting. Only these caps go into .env.limits.
#   2. Estimates the worst-case RAM of the enabled services and warns when it
#      does not fit. The LiteLLM resource manager runs one job per hardware
#      class, so only the largest service of the CPU group and the largest of
#      the CUDA group count toward the peak. Every other enabled service counts
#      in full. Nothing is shrunk to fit: a limit below what a model needs to
#      load gets the container OOM-killed on first use.

set -euo pipefail

readonly OUT=".env.limits"
readonly ENV_FILE=".env"
readonly COMPOSE_FILE_PATH="docker-compose.yml"
readonly MB_PER_GB=1024
readonly OS_RESERVE_MIN_MB=2048
readonly OS_RESERVE_PERCENT=5
readonly DEFAULT_SAB_REPLICAS=5
readonly GROUP_ALWAYS="always"
readonly GROUP_OPTIONAL="optional"
readonly GROUP_CPU="cpu"
readonly GROUP_CUDA="cuda"

# Services that share the LiteLLM hardware lock. Each has a _CUDA twin.
readonly LOCK_GROUP_SERVICES="OLLAMA TALKIES SDCPP VLLM LLAMACPP AUDIOLLA FLICKIES PREDICTALOT DECIDEALOT"
readonly ALWAYS_ON_SERVICES="NGINX LITELLM POSTGRES REDIS PROXQ MCP"
readonly OPTIONAL_SERVICES="CLAUDEBOX PIBOX PIBOX_ZAI HYBRIDS3 CLOUDFLARED SEARXNG TELETHON TAILSCALE MAILBOX PISTON"

log() {
    local level="$1"
    shift
    printf '{"time":"%s","level":"%s","file":"%s","line":%d,"func":"%s","msg":"%s"}\n' \
        "$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')" "$level" "${BASH_SOURCE[1]##*/}" \
        "${BASH_LINENO[0]}" "${FUNCNAME[1]:-main}" "$*" >&2
}

# env_value <NAME> → value of NAME in .env with whitespace stripped, or empty.
env_value() {
    [[ -f "$ENV_FILE" ]] || return 0
    # grep exits 1 when the variable is absent, which means "not set" here.
    grep -E "^$1=" "$ENV_FILE" | tail -1 | cut -d= -f2 | tr -d '[:space:]' || true
}

is_enabled() {
    [[ "$(env_value "$1")" == "1" ]]
}

# compose_default <VAR> → the default in `${VAR:-default}` from compose.
compose_default() {
    grep -m1 -oE "\\\$\\{$1:-[^}]+\\}" "$COMPOSE_FILE_PATH" | sed -E 's/.*:-(.*)\}/\1/'
}

# setting <VAR> → .env value if set, else the compose default.
setting() {
    local value
    value=$(env_value "$1")
    [[ -n "$value" ]] || value=$(compose_default "$1")
    echo "$value"
}

# to_mb <size> → MB for docker sizes like 512m, 12g, 1.5g.
to_mb() {
    awk -v size="$1" -v per_gb="$MB_PER_GB" 'BEGIN {
        unit = tolower(substr(size, length(size)))
        amount = substr(size, 1, length(size) - 1) + 0
        if (unit == "g") printf "%d", amount * per_gb
        else if (unit == "m") printf "%d", amount
        else if (unit == "k") printf "%d", amount / per_gb
        else printf "%d", size / (per_gb * per_gb)
    }'
}

fmt() {
    awk -v mb="$1" -v per_gb="$MB_PER_GB" 'BEGIN {
        if (mb >= per_gb) printf "%.1fg", mb / per_gb
        else printf "%dm", mb
    }'
}

total_ram_mb=$(awk '/MemTotal/ { printf "%d", $2 / 1024 }' /proc/meminfo)
total_cores=$(nproc)
os_reserve_mb=$((total_ram_mb * OS_RESERVE_PERCENT / 100))
((os_reserve_mb < OS_RESERVE_MIN_MB)) && os_reserve_mb=$OS_RESERVE_MIN_MB
budget_mb=$((total_ram_mb - os_reserve_mb))

services=()
peak_mb=0
cpu_group_max_mb=0
cpu_group_max_name=""
cuda_group_max_mb=0
cuda_group_max_name=""

# add_service <PREFIX> <group> [replicas]
add_service() {
    local prefix="$1" group="$2" replicas="${3:-1}"
    local mem_mb
    mem_mb=$(to_mb "$(setting "${prefix}_MEM_LIMIT")")
    services+=("$prefix $mem_mb $group $replicas")

    if [[ "$group" == "$GROUP_CPU" ]]; then
        if ((mem_mb > cpu_group_max_mb)); then
            cpu_group_max_mb=$mem_mb
            cpu_group_max_name=$prefix
        fi
        return 0
    fi
    if [[ "$group" == "$GROUP_CUDA" ]]; then
        if ((mem_mb > cuda_group_max_mb)); then
            cuda_group_max_mb=$mem_mb
            cuda_group_max_name=$prefix
        fi
        return 0
    fi
    peak_mb=$((peak_mb + mem_mb * replicas))
}

for service in $ALWAYS_ON_SERVICES; do
    add_service "$service" "$GROUP_ALWAYS"
done

for service in $LOCK_GROUP_SERVICES; do
    is_enabled "$service" && add_service "$service" "$GROUP_CPU"
    is_enabled "${service}_CUDA" && add_service "${service}_CUDA" "$GROUP_CUDA"
done

for service in $OPTIONAL_SERVICES; do
    is_enabled "$service" && add_service "$service" "$GROUP_OPTIONAL"
done

if is_enabled LIBRECHAT; then
    add_service LIBRECHAT "$GROUP_OPTIONAL"
    add_service LIBRECHAT_MONGO "$GROUP_OPTIONAL"
fi

if is_enabled BROWSER; then
    sab_replicas=$(env_value STEALTHY_AUTO_BROWSE_NUM_REPLICAS)
    add_service SAB "$GROUP_OPTIONAL" "${sab_replicas:-$DEFAULT_SAB_REPLICAS}"
    add_service SAB_REDIS "$GROUP_OPTIONAL"
    add_service SAB_PROXY "$GROUP_OPTIONAL"
fi

peak_mb=$((peak_mb + cpu_group_max_mb + cuda_group_max_mb))

echo ""
echo "System: ${total_ram_mb} MB RAM, ${total_cores} cores"
echo "Budget: ${budget_mb} MB after a ${os_reserve_mb} MB OS reserve"
echo ""
printf "%-22s %9s %6s  %s\n" "Service" "mem_limit" "cpus" "Group"
printf "%-22s %9s %6s  %s\n" "-------" "---------" "----" "-----"

cpu_caps=()
for entry in "${services[@]}"; do
    read -r prefix mem_mb group replicas <<<"$entry"
    cpus=$(setting "${prefix}_CPUS")
    if awk -v cpus="$cpus" -v cores="$total_cores" 'BEGIN { exit !(cpus > cores) }'; then
        cpus="${total_cores}.0"
        cpu_caps+=("${prefix}_CPUS=${cpus}")
    fi

    name=$prefix
    ((replicas > 1)) && name="${prefix} (x${replicas})"
    label=$group
    [[ "$group" == "$GROUP_CPU" ]] && label="CPU lock, one at a time"
    [[ "$group" == "$GROUP_CUDA" ]] && label="CUDA lock, one at a time"
    printf "%-22s %9s %6s  %s\n" "$name" "$(fmt "$mem_mb")" "$cpus" "$label"
done

echo ""
echo "Worst-case RAM: $(fmt "$peak_mb") of $(fmt "$budget_mb")"
if [[ -n "$cpu_group_max_name" ]]; then
    echo "  CPU lock group counted at its largest member: ${cpu_group_max_name} $(fmt "$cpu_group_max_mb")"
fi
if [[ -n "$cuda_group_max_name" ]]; then
    echo "  CUDA lock group counted at its largest member: ${cuda_group_max_name} $(fmt "$cuda_group_max_mb")"
fi

if ((peak_mb > budget_mb)); then
    log WARN "enabled services can use more RAM than this host has: peak_mb=${peak_mb} budget_mb=${budget_mb}. Disable services in .env, or lower a limit only when that service's models still fit, since a limit below a model's load size gets the container OOM-killed"
fi

{
    echo "# Auto-generated by: make limits"
    echo "# System: ${total_ram_mb}MB RAM, ${total_cores} cores"
    echo "# Memory limits come from the docker-compose.yml defaults. This file only"
    echo "# caps CPU limits that exceed the host core count."
    for cap in "${cpu_caps[@]}"; do
        echo "$cap"
    done
} >"$OUT"

echo ""
echo "Written to: $OUT (${#cpu_caps[@]} CPU caps)"
echo "Restart to apply: make restart"
echo ""
