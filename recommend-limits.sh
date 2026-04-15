#!/usr/bin/env bash
# Reads system RAM, swap, and CPU core count, then writes .env.limits with
# recommended resource limits for each service. docker-compose.yml reads these
# via ${VAR:-default} substitution. Run: make limits
#
# MAXUSE: percentage of total system resources the stack may use (default: 90).
#   MAXUSE=80 make limits
#
# Swap allocation: each service gets a proportional share of total swap based
# on its RAM allocation. Hard cap: 10× mem. Minimum: 2× mem.

set -euo pipefail

OUT=".env.limits"

# ── System info ───────────────────────────────────────────────────────────────

total_ram_mb=$(awk '/MemTotal/ { printf "%d", $2/1024 }' /proc/meminfo)
total_swap_mb=$(awk '/SwapTotal/ { printf "%d", $2/1024 }' /proc/meminfo)
total_cores=$(nproc)

maxuse=${MAXUSE:-100}
if [ "$maxuse" -lt 10 ] || [ "$maxuse" -gt 100 ]; then
    echo "ERROR: MAXUSE must be between 10 and 100 (got: $maxuse)" >&2
    exit 1
fi

# Scale available resources by MAXUSE percentage
effective_ram_mb=$(( total_ram_mb * maxuse / 100 ))
effective_swap_mb=$(( total_swap_mb * maxuse / 100 ))
effective_cores=$(awk -v cores="$total_cores" -v pct="$maxuse" 'BEGIN { printf "%.2f", cores * pct / 100 }')

echo ""
echo "System info:"
echo "  RAM:   ${total_ram_mb} MB  (effective: ${effective_ram_mb} MB at ${maxuse}%)"
echo "  Swap:  ${total_swap_mb} MB  (effective: ${effective_swap_mb} MB at ${maxuse}%)"
echo "  Cores: ${total_cores}  (effective: ${effective_cores} at ${maxuse}%)"
echo "  MAXUSE: ${maxuse}%"
echo ""

# ── Helpers ───────────────────────────────────────────────────────────────────

# mem <pct_of_effective_ram> <floor_mb>  → MB
mem() {
    local pct=$1 floor=$2
    local val=$(( effective_ram_mb * pct / 100 ))
    echo $(( val < floor ? floor : val ))
}

# swap <mem_mb>  → memswap MB (mem + proportional swap share, capped at 10×, min 2×)
swap() {
    local m=$1
    awk -v mem="$m" -v eff_ram="$effective_ram_mb" -v eff_swap="$effective_swap_mb" '
    BEGIN {
        swap_share = eff_swap * (mem / eff_ram)
        memswap = mem + swap_share
        if (memswap > mem * 10) memswap = mem * 10
        if (memswap < mem * 2)  memswap = mem * 2
        printf "%d\n", memswap
    }'
}

# cpu <pct_of_effective_cores> <floor_tenths>  → cpus (1 decimal)
cpu() {
    local pct=$1 floor_tenths=$2
    awk -v cores="$effective_cores" -v p="$pct" -v f="$floor_tenths" \
        'BEGIN { v = cores * p / 100; min = f/10; printf "%.1f\n", (v < min ? min : v) }'
}

# fmt <mb>  → "Xm" or "X.Xg" (no trailing newline, for env file)
fmt() {
    awk -v m="$1" 'BEGIN {
        if (m >= 1024) { printf "%.1fg", m/1024 }
        else           { printf "%dm", m }
    }'
}

# ── Allocations ───────────────────────────────────────────────────────────────
# RAM % targets — leaves ~18% for OS/kernel/non-containerised processes.
# CPU % targets can exceed 100% — they are hard caps per service, not
# guaranteed allocations. Services don't all peak at the same time.

#                          RAM%  floor(MB)   CPU%  floor(0.1 cores)
nginx_init_mem=$(  mem  1   64 ); nginx_init_swap=$(  swap $nginx_init_mem  ); nginx_init_cpu=$(  cpu  2  2 )
nginx_mem=$(       mem  1   64 ); nginx_swap=$(       swap $nginx_mem       ); nginx_cpu=$(       cpu  2  2 )
litellm_mem=$(     mem  9  512 ); litellm_swap=$(     swap $litellm_mem     ); litellm_cpu=$(     cpu 25  4 )
claudebox_mem=$(   mem  4  256 ); claudebox_swap=$(   swap $claudebox_mem   ); claudebox_cpu=$(   cpu 15  2 )
cbzai_mem=$(       mem  4  256 ); cbzai_swap=$(       swap $cbzai_mem       ); cbzai_cpu=$(       cpu 15  2 )
hybrids3_mem=$(    mem  2  128 ); hybrids3_swap=$(    swap $hybrids3_mem    ); hybrids3_cpu=$(    cpu  3  1 )
redis_mem=$(       mem  2  128 ); redis_swap=$(       swap $redis_mem       ); redis_cpu=$(       cpu  2  1 )
postgres_mem=$(    mem  3  256 ); postgres_swap=$(    swap $postgres_mem    ); postgres_cpu=$(    cpu  8  1 )
sab_redis_mem=$(   mem  1   64 ); sab_redis_swap=$(   swap $sab_redis_mem   ); sab_redis_cpu=$(   cpu  1  1 )
sab_mem=$(         mem  3  128 ); sab_swap=$(         swap $sab_mem         ); sab_cpu=$(         cpu 10  2 )
sab_proxy_mem=$(   mem  1   64 ); sab_proxy_swap=$(   swap $sab_proxy_mem   ); sab_proxy_cpu=$(   cpu  2  1 )
speaches_mem=$(    mem 15  512 ); speaches_swap=$(    swap $speaches_mem    ); speaches_cpu=$(    cpu 25  2 )
ollama_mem=$(      mem 24  512 ); ollama_swap=$(      swap $ollama_mem      ); ollama_cpu=$(      cpu 40  2 )
ollama_pull_mem=$( mem  2  128 ); ollama_pull_swap=$( swap $ollama_pull_mem ); ollama_pull_cpu=$( cpu  5  1 )
cloudflared_mem=$( mem  1   64 ); cloudflared_swap=$( swap $cloudflared_mem ); cloudflared_cpu=$( cpu  1  1 )

# ── Print allocation table ────────────────────────────────────────────────────

printf "%-30s %8s %10s %6s\n" "Service" "mem_limit" "memswap" "cpus"
printf "%-30s %8s %10s %6s\n" "-------" "---------" "-------" "----"

row() { printf "%-30s %8s %10s %6s\n" "$1" "$(fmt $2)" "$(fmt $3)" "$4"; }

row "nginx-auth-init (one-shot)"  $nginx_init_mem  $nginx_init_swap  $nginx_init_cpu
row "nginx"                       $nginx_mem        $nginx_swap        $nginx_cpu
row "litellm"                     $litellm_mem      $litellm_swap      $litellm_cpu
row "claudebox"                   $claudebox_mem    $claudebox_swap    $claudebox_cpu
row "claudebox-zai"               $cbzai_mem        $cbzai_swap        $cbzai_cpu
row "hybrids3"                    $hybrids3_mem     $hybrids3_swap     $hybrids3_cpu
row "redis"                       $redis_mem        $redis_swap        $redis_cpu
row "postgres"                    $postgres_mem     $postgres_swap     $postgres_cpu
row "stealthy-auto-browse-redis"  $sab_redis_mem    $sab_redis_swap    $sab_redis_cpu
row "stealthy-auto-browse (each)" $sab_mem          $sab_swap          $sab_cpu
row "stealthy-auto-browse-proxy"  $sab_proxy_mem    $sab_proxy_swap    $sab_proxy_cpu
row "speaches"                    $speaches_mem     $speaches_swap     $speaches_cpu
row "ollama"                      $ollama_mem       $ollama_swap       $ollama_cpu
row "ollama-pull (one-shot)"      $ollama_pull_mem  $ollama_pull_swap  $ollama_pull_cpu
row "cloudflared"                 $cloudflared_mem  $cloudflared_swap  $cloudflared_cpu

total_mem=$(( nginx_mem + litellm_mem + claudebox_mem + cbzai_mem + hybrids3_mem +
              redis_mem + postgres_mem + sab_redis_mem + sab_mem * 5 +
              sab_proxy_mem + speaches_mem + ollama_mem + cloudflared_mem ))
echo ""
echo "Total max RAM (all persistent services): $(fmt $total_mem)"
echo "  ($(( total_mem * 100 / total_ram_mb ))% of total RAM, MAXUSE=${maxuse}%)"

# ── Write .env.limits ─────────────────────────────────────────────────────────

cat > "$OUT" << EOF
# Auto-generated by: make limits
# System: ${total_ram_mb}MB RAM, ${total_swap_mb}MB swap, ${total_cores} cores (MAXUSE=${maxuse}%)
# Regenerate any time: make limits  or  MAXUSE=80 make limits

NGINX_AUTH_INIT_MEM_LIMIT=$(fmt $nginx_init_mem)
NGINX_AUTH_INIT_MEMSWAP_LIMIT=$(fmt $nginx_init_swap)
NGINX_AUTH_INIT_CPUS=${nginx_init_cpu}

NGINX_MEM_LIMIT=$(fmt $nginx_mem)
NGINX_MEMSWAP_LIMIT=$(fmt $nginx_swap)
NGINX_CPUS=${nginx_cpu}

LITELLM_MEM_LIMIT=$(fmt $litellm_mem)
LITELLM_MEMSWAP_LIMIT=$(fmt $litellm_swap)
LITELLM_CPUS=${litellm_cpu}

CLAUDEBOX_MEM_LIMIT=$(fmt $claudebox_mem)
CLAUDEBOX_MEMSWAP_LIMIT=$(fmt $claudebox_swap)
CLAUDEBOX_CPUS=${claudebox_cpu}

CLAUDEBOX_ZAI_MEM_LIMIT=$(fmt $cbzai_mem)
CLAUDEBOX_ZAI_MEMSWAP_LIMIT=$(fmt $cbzai_swap)
CLAUDEBOX_ZAI_CPUS=${cbzai_cpu}

HYBRIDS3_MEM_LIMIT=$(fmt $hybrids3_mem)
HYBRIDS3_MEMSWAP_LIMIT=$(fmt $hybrids3_swap)
HYBRIDS3_CPUS=${hybrids3_cpu}

REDIS_MEM_LIMIT=$(fmt $redis_mem)
REDIS_MEMSWAP_LIMIT=$(fmt $redis_swap)
REDIS_CPUS=${redis_cpu}

POSTGRES_MEM_LIMIT=$(fmt $postgres_mem)
POSTGRES_MEMSWAP_LIMIT=$(fmt $postgres_swap)
POSTGRES_CPUS=${postgres_cpu}

SAB_REDIS_MEM_LIMIT=$(fmt $sab_redis_mem)
SAB_REDIS_MEMSWAP_LIMIT=$(fmt $sab_redis_swap)
SAB_REDIS_CPUS=${sab_redis_cpu}

SAB_MEM_LIMIT=$(fmt $sab_mem)
SAB_MEMSWAP_LIMIT=$(fmt $sab_swap)
SAB_CPUS=${sab_cpu}

SAB_PROXY_MEM_LIMIT=$(fmt $sab_proxy_mem)
SAB_PROXY_MEMSWAP_LIMIT=$(fmt $sab_proxy_swap)
SAB_PROXY_CPUS=${sab_proxy_cpu}

SPEACHES_MEM_LIMIT=$(fmt $speaches_mem)
SPEACHES_MEMSWAP_LIMIT=$(fmt $speaches_swap)
SPEACHES_CPUS=${speaches_cpu}

OLLAMA_MEM_LIMIT=$(fmt $ollama_mem)
OLLAMA_MEMSWAP_LIMIT=$(fmt $ollama_swap)
OLLAMA_CPUS=${ollama_cpu}

OLLAMA_PULL_MEM_LIMIT=$(fmt $ollama_pull_mem)
OLLAMA_PULL_MEMSWAP_LIMIT=$(fmt $ollama_pull_swap)
OLLAMA_PULL_CPUS=${ollama_pull_cpu}

CLOUDFLARED_MEM_LIMIT=$(fmt $cloudflared_mem)
CLOUDFLARED_MEMSWAP_LIMIT=$(fmt $cloudflared_swap)
CLOUDFLARED_CPUS=${cloudflared_cpu}
EOF

echo ""
echo "Written to: $OUT"
echo "Review it, then restart: make restart"
echo ""
