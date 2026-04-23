#!/usr/bin/env bash
# Reads system RAM, swap, and CPU core count, then writes .env.limits with
# recommended resource limits scaled to the enabled service set.
#
# Proportional scaling: concurrent RAM of all enabled services is estimated and
# scaled to fit within the effective RAM budget. Enabling more services means
# each gets a smaller slice.
#
# Resource manager awareness: CUDA services (ollama-cuda, speaches-cuda,
# qwen3-cuda-tts) share one model slot — only one has models loaded at a time.
# Peak concurrent CUDA RAM = max(three active allocations) + 2 × idle overhead.
#
# MAXUSE: percentage of total system resources the stack may use (default: 100).
#   MAXUSE=80 make limits
#
# Swap: each service gets a proportional share of total swap based on its RAM
# allocation. Hard cap: 10× mem. Minimum: 2× mem.

set -euo pipefail

OUT=".env.limits"

# ── System info ───────────────────────────────────────────────────────────────

total_ram_mb=$(awk '/MemTotal/ { printf "%d", $2/1024 }' /proc/meminfo)
total_swap_mb=$(awk '/SwapTotal/ { printf "%d", $2/1024 }' /proc/meminfo)
total_cores=$(nproc)

# ── Feature flags ─────────────────────────────────────────────────────────────

sab_replicas=5
litellm_workers=4
flag_cuda=0; flag_speaches=0; flag_ollama=0; flag_browser=0
flag_claudebox=0; flag_cbzai=0; flag_hybrids3=0; flag_cloudflared=0
flag_librechat=0; flag_mcp=0; flag_sdcpp=0

if [ -f .env ]; then
    _v() { grep -E "^$1=" .env | cut -d= -f2 | tr -d '[:space:]' || true; }
    val=$(_v STEALTHY_AUTO_BROWSE_NUM_REPLICAS); [ -n "$val" ] && sab_replicas=$val
    val=$(_v LITELLM_WORKERS); [ -n "$val" ] && litellm_workers=$val
    [ "$(_v CUDA)" = "1" ]          && flag_cuda=1
    [ "$(_v SPEACHES)" = "1" ]      && flag_speaches=1
    [ "$(_v OLLAMA)" = "1" ]        && flag_ollama=1
    [ "$(_v BROWSER)" = "1" ]       && flag_browser=1
    [ "$(_v CLAUDEBOX)" = "1" ]     && flag_claudebox=1
    [ "$(_v CLAUDEBOX_ZAI)" = "1" ] && flag_cbzai=1
    [ "$(_v HYBRIDS3)" = "1" ]      && flag_hybrids3=1
    [ "$(_v CLOUDFLARED)" = "1" ]   && flag_cloudflared=1
    [ "$(_v LIBRECHAT)" = "1" ]    && flag_librechat=1
    [ "$(_v SDCPP)" = "1" ]       && flag_sdcpp=1
    # mcp auto-enabled when image/TTS providers active
    [ "$(_v HUGGINGFACE)" = "1" ] || [ "$(_v OPENAI)" = "1" ] || \
        [ "$(_v SPEACHES)" = "1" ] || [ "$(_v CUDA)" = "1" ] || \
        [ "$(_v SDCPP)" = "1" ] && flag_mcp=1
fi

# ── Resource budget ───────────────────────────────────────────────────────────

maxuse=${MAXUSE:-100}
if [ "$maxuse" -lt 10 ] || [ "$maxuse" -gt 100 ]; then
    echo "ERROR: MAXUSE must be between 10 and 100 (got: $maxuse)" >&2
    exit 1
fi

effective_ram_mb=$(( total_ram_mb * maxuse / 100 ))
effective_swap_mb=$(( total_swap_mb * maxuse / 100 ))
effective_cores=$(awk -v cores="$total_cores" -v pct="$maxuse" \
    'BEGIN { printf "%.2f", cores * pct / 100 }')

echo ""
echo "System info:"
echo "  RAM:   ${total_ram_mb} MB  (effective: ${effective_ram_mb} MB at ${maxuse}%)"
echo "  Swap:  ${total_swap_mb} MB  (effective: ${effective_swap_mb} MB at ${maxuse}%)"
echo "  Cores: ${total_cores}  (effective: ${effective_cores} at ${maxuse}%)"
echo "  MAXUSE: ${maxuse}%"
echo "  Enabled: cuda=${flag_cuda} speaches=${flag_speaches} ollama=${flag_ollama} sdcpp=${flag_sdcpp} browser=${flag_browser} claudebox=${flag_claudebox} cbzai=${flag_cbzai} hybrids3=${flag_hybrids3} cloudflared=${flag_cloudflared} librechat=${flag_librechat} mcp=${flag_mcp}"
echo ""

# ── Helpers ───────────────────────────────────────────────────────────────────

# raw_mem <pct_of_effective_ram> <floor_mb>  → MB
raw_mem() {
    local pct=$1 floor=$2
    local val=$(( effective_ram_mb * pct / 100 ))
    echo $(( val < floor ? floor : val ))
}

# swap <mem_mb>  → memswap MB (mem + proportional swap share, capped at 10×, min 2×)
_swap() {
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

# fmt <mb>  → "Xm" or "X.Xg"
fmt() {
    awk -v m="$1" 'BEGIN {
        if (m >= 1024) { printf "%.1fg", m/1024 }
        else           { printf "%dm", m }
    }'
}

# scale_mem <raw_mb> <floor_mb> <scale_pct>  → scaled MB (never below floor)
scale_mem() {
    local raw=$1 floor=$2 sc=$3
    local scaled=$(( raw * sc / 100 ))
    echo $(( scaled < floor ? floor : scaled ))
}

# ── Raw allocations (% of effective RAM, before scaling) ─────────────────────
# These are proportions — they get scaled down if concurrent total exceeds budget.
# CPU % targets can exceed 100% — they are hard caps, not guaranteed allocations.

#                            RAM%  floor(MB)
nginx_init_raw=$(  raw_mem  1   64 )
nginx_raw=$(       raw_mem  1   64 )
postgres_raw=$(    raw_mem  3  256 )
redis_raw=$(       raw_mem  2  128 )
claudebox_raw=$(   raw_mem  4  256 )
cbzai_raw=$(       raw_mem  4  256 )
hybrids3_raw=$(    raw_mem  2  128 )
sab_redis_raw=$(   raw_mem  1   64 )
sab_raw=$(         raw_mem  3  128 )
sab_proxy_raw=$(   raw_mem  1   64 )
speaches_raw=$(    raw_mem 15  512 )
ollama_raw=$(      raw_mem 24  512 )
ollama_pull_raw=$( raw_mem  2  128 )
cloudflared_raw=$( raw_mem  1   64 )
proxq_raw=$(       raw_mem  2  128 )
mcp_raw=$(         raw_mem  2  128 )
librechat_raw=$(   raw_mem  3  256 )
librechat_mongo_raw=$( raw_mem 3 256 )
# sdcpp — FLUX model weights in RAM (~12GB for q4_0 + encoders)
sdcpp_raw=$(            raw_mem 15  512 )
sdcpp_pull_raw=$(       raw_mem  1  128 )
# CUDA — models live in VRAM; these cover process RAM, KV cache, audio buffers
sdcpp_cuda_raw=$(       raw_mem 15  512 )
ollama_cuda_raw=$(      raw_mem  6  256 )
speaches_cuda_raw=$(    raw_mem  4  256 )
qwen3_cuda_tts_raw=$(   raw_mem  4  512 )

# CPU allocations (not scaled — CPU is time-shared, not a hard budget)
nginx_init_cpu=$(      cpu  2  2 )
nginx_cpu=$(           cpu  2  2 )
litellm_cpu=$(         cpu 25  $litellm_workers )
claudebox_cpu=$(       cpu 15  2 )
cbzai_cpu=$(           cpu 15  2 )
hybrids3_cpu=$(        cpu  3  1 )
redis_cpu=$(           cpu  2  1 )
postgres_cpu=$(        cpu  8  1 )
sab_redis_cpu=$(       cpu  1  1 )
sab_cpu=$(             cpu 10  2 )
sab_proxy_cpu=$(       cpu  2  1 )
speaches_cpu=$(        cpu 25  2 )
ollama_cpu=$(          cpu 40  2 )
ollama_pull_cpu=$(     cpu  5  1 )
cloudflared_cpu=$(     cpu  1  1 )
proxq_cpu=$(           cpu  5  1 )
mcp_cpu=$(             cpu  3  1 )
librechat_cpu=$(       cpu  8  1 )
librechat_mongo_cpu=$( cpu  5  1 )
sdcpp_cpu=$(           cpu 40  2 )
sdcpp_pull_cpu=$(      cpu  2  1 )
sdcpp_cuda_cpu=$(      cpu 40  2 )
ollama_cuda_cpu=$(     cpu 30  2 )
speaches_cuda_cpu=$(   cpu 20  2 )
qwen3_cuda_tts_cpu=$(  cpu 20  2 )

# ── Concurrent RAM estimate (resource-manager-aware) ─────────────────────────
# Only count enabled services. CUDA group: resource manager ensures only one
# service has models loaded — count max(three) + 2 × idle overhead (256 MB each).

cuda_idle=256  # MB per idle CUDA container (models unloaded from VRAM)

concurrent=0
concurrent=$(( concurrent + nginx_raw + postgres_raw + redis_raw + proxq_raw ))
[ "$flag_claudebox" = "1" ]   && concurrent=$(( concurrent + claudebox_raw ))
[ "$flag_cbzai" = "1" ]       && concurrent=$(( concurrent + cbzai_raw ))
[ "$flag_hybrids3" = "1" ]    && concurrent=$(( concurrent + hybrids3_raw ))
[ "$flag_speaches" = "1" ]    && concurrent=$(( concurrent + speaches_raw ))
[ "$flag_ollama" = "1" ]      && concurrent=$(( concurrent + ollama_raw ))
if [ "$flag_sdcpp" = "1" ]; then
    if [ "$flag_cuda" = "1" ]; then
        concurrent=$(( concurrent + sdcpp_cuda_raw ))
    else
        concurrent=$(( concurrent + sdcpp_raw ))
    fi
fi
[ "$flag_cloudflared" = "1" ] && concurrent=$(( concurrent + cloudflared_raw ))
[ "$flag_mcp" = "1" ]        && concurrent=$(( concurrent + mcp_raw ))
[ "$flag_librechat" = "1" ]  && concurrent=$(( concurrent + librechat_raw + librechat_mongo_raw ))
if [ "$flag_browser" = "1" ]; then
    concurrent=$(( concurrent + sab_redis_raw + sab_raw * sab_replicas + sab_proxy_raw ))
fi
if [ "$flag_cuda" = "1" ]; then
    cuda_max=$ollama_cuda_raw
    [ "$speaches_cuda_raw" -gt "$cuda_max" ]    && cuda_max=$speaches_cuda_raw
    [ "$qwen3_cuda_tts_raw" -gt "$cuda_max" ]   && cuda_max=$qwen3_cuda_tts_raw
    [ "$flag_sdcpp" = "1" ] && [ "$sdcpp_cuda_raw" -gt "$cuda_max" ] && cuda_max=$sdcpp_cuda_raw
    concurrent=$(( concurrent + cuda_max + 2 * cuda_idle ))
fi

# ── Scale factor ──────────────────────────────────────────────────────────────

scale=100
if [ "$concurrent" -gt "$effective_ram_mb" ] && [ "$concurrent" -gt 0 ]; then
    scale=$(( effective_ram_mb * 100 / concurrent ))
    echo "Note: scaling allocations by ${scale}% to fit within ${effective_ram_mb} MB"
    echo "  (concurrent peak ${concurrent} MB > budget ${effective_ram_mb} MB)"
    echo ""
fi

# ── Final allocations (scaled) ────────────────────────────────────────────────

nginx_init_mem=$(  scale_mem $nginx_init_raw    64 $scale ); nginx_init_swap=$(  _swap $nginx_init_mem )
nginx_mem=$(       scale_mem $nginx_raw         64 $scale ); nginx_swap=$(       _swap $nginx_mem )
postgres_mem=$(    scale_mem $postgres_raw     256 $scale ); postgres_swap=$(    _swap $postgres_mem )
redis_mem=$(       scale_mem $redis_raw        128 $scale ); redis_swap=$(       _swap $redis_mem )
claudebox_mem=$(   scale_mem $claudebox_raw    256 $scale ); claudebox_swap=$(   _swap $claudebox_mem )
cbzai_mem=$(       scale_mem $cbzai_raw        256 $scale ); cbzai_swap=$(       _swap $cbzai_mem )
hybrids3_mem=$(    scale_mem $hybrids3_raw     128 $scale ); hybrids3_swap=$(    _swap $hybrids3_mem )
sab_redis_mem=$(   scale_mem $sab_redis_raw     64 $scale ); sab_redis_swap=$(   _swap $sab_redis_mem )
sab_mem=$(         scale_mem $sab_raw          128 $scale ); sab_swap=$(         _swap $sab_mem )
sab_proxy_mem=$(   scale_mem $sab_proxy_raw     64 $scale ); sab_proxy_swap=$(   _swap $sab_proxy_mem )
speaches_mem=$(    scale_mem $speaches_raw     512 $scale ); speaches_swap=$(    _swap $speaches_mem )
ollama_mem=$(      scale_mem $ollama_raw       512 $scale ); ollama_swap=$(      _swap $ollama_mem )
ollama_pull_mem=$( scale_mem $ollama_pull_raw  128 $scale ); ollama_pull_swap=$( _swap $ollama_pull_mem )
cloudflared_mem=$( scale_mem $cloudflared_raw   64 $scale ); cloudflared_swap=$( _swap $cloudflared_mem )
proxq_mem=$(       scale_mem $proxq_raw       128 $scale ); proxq_swap=$(       _swap $proxq_mem )
mcp_mem=$(         scale_mem $mcp_raw         128 $scale ); mcp_swap=$(         _swap $mcp_mem )
librechat_mem=$(   scale_mem $librechat_raw   256 $scale ); librechat_swap=$(   _swap $librechat_mem )
librechat_mongo_mem=$( scale_mem $librechat_mongo_raw 256 $scale ); librechat_mongo_swap=$( _swap $librechat_mongo_mem )
sdcpp_mem=$(            scale_mem $sdcpp_raw            512 $scale ); sdcpp_swap=$(            _swap $sdcpp_mem )
sdcpp_pull_mem=$(       scale_mem $sdcpp_pull_raw       128 $scale ); sdcpp_pull_swap=$(       _swap $sdcpp_pull_mem )
# CUDA: each gets its full scaled allocation (must handle being the active service)
sdcpp_cuda_mem=$(       scale_mem $sdcpp_cuda_raw       512 $scale ); sdcpp_cuda_swap=$(       _swap $sdcpp_cuda_mem )
ollama_cuda_mem=$(      scale_mem $ollama_cuda_raw      256 $scale ); ollama_cuda_swap=$(      _swap $ollama_cuda_mem )
speaches_cuda_mem=$(    scale_mem $speaches_cuda_raw    256 $scale ); speaches_cuda_swap=$(    _swap $speaches_cuda_mem )
qwen3_cuda_tts_mem=$(   scale_mem $qwen3_cuda_tts_raw   512 $scale ); qwen3_cuda_tts_swap=$(   _swap $qwen3_cuda_tts_mem )

# ── Print allocation table ────────────────────────────────────────────────────

printf "%-35s %8s %10s %6s\n" "Service" "mem_limit" "memswap" "cpus"
printf "%-35s %8s %10s %6s\n" "-------" "---------" "-------" "----"

row() { printf "%-35s %8s %10s %6s\n" "$1" "$(fmt $2)" "$(fmt $3)" "$4"; }

row "nginx-auth-init (one-shot)"    $nginx_init_mem  $nginx_init_swap  $nginx_init_cpu
row "nginx"                         $nginx_mem        $nginx_swap        $nginx_cpu
printf "%-35s %8s %10s %6s\n" "litellm" "none" "none" "$litellm_cpu"
row "postgres"                      $postgres_mem     $postgres_swap     $postgres_cpu
row "redis"                         $redis_mem        $redis_swap        $redis_cpu
row "proxq"                         $proxq_mem        $proxq_swap        $proxq_cpu
[ "$flag_claudebox" = "1" ] && row "claudebox"              $claudebox_mem  $claudebox_swap  $claudebox_cpu
[ "$flag_cbzai" = "1" ]     && row "claudebox-zai"          $cbzai_mem      $cbzai_swap      $cbzai_cpu
[ "$flag_hybrids3" = "1" ]  && row "hybrids3"               $hybrids3_mem   $hybrids3_swap   $hybrids3_cpu
if [ "$flag_browser" = "1" ]; then
    row "stealthy-auto-browse-redis"    $sab_redis_mem  $sab_redis_swap  $sab_redis_cpu
    row "stealthy-auto-browse (×${sab_replicas})" $sab_mem $sab_swap $sab_cpu
    row "stealthy-auto-browse-proxy"    $sab_proxy_mem  $sab_proxy_swap  $sab_proxy_cpu
fi
[ "$flag_speaches" = "1" ]    && row "speaches"              $speaches_mem   $speaches_swap   $speaches_cpu
[ "$flag_ollama" = "1" ]      && row "ollama"                $ollama_mem     $ollama_swap     $ollama_cpu
[ "$flag_ollama" = "1" ]      && row "ollama-pull (one-shot)" $ollama_pull_mem $ollama_pull_swap $ollama_pull_cpu
if [ "$flag_sdcpp" = "1" ] && [ "$flag_cuda" != "1" ]; then
    row "sdcpp"                        $sdcpp_mem        $sdcpp_swap        $sdcpp_cpu
    row "sdcpp-pull (one-shot)"        $sdcpp_pull_mem   $sdcpp_pull_swap   $sdcpp_pull_cpu
fi
[ "$flag_cloudflared" = "1" ] && row "cloudflared"           $cloudflared_mem $cloudflared_swap $cloudflared_cpu
[ "$flag_mcp" = "1" ]        && row "mcp"                   $mcp_mem        $mcp_swap        $mcp_cpu
if [ "$flag_librechat" = "1" ]; then
    row "librechat"                     $librechat_mem       $librechat_swap       $librechat_cpu
    row "librechat-mongodb"             $librechat_mongo_mem $librechat_mongo_swap  $librechat_mongo_cpu
fi
if [ "$flag_cuda" = "1" ]; then
    echo ""
    echo "CUDA services (one model slot shared via resource manager):"
    [ "$flag_sdcpp" = "1" ] && row "sdcpp-cuda"             $sdcpp_cuda_mem        $sdcpp_cuda_swap        $sdcpp_cuda_cpu
    [ "$flag_sdcpp" = "1" ] && row "sdcpp-pull (one-shot)"  $sdcpp_pull_mem        $sdcpp_pull_swap        $sdcpp_pull_cpu
    row "ollama-cuda"                   $ollama_cuda_mem       $ollama_cuda_swap       $ollama_cuda_cpu
    row "speaches-cuda"                 $speaches_cuda_mem     $speaches_cuda_swap     $speaches_cuda_cpu
    row "qwen3-cuda-tts"                $qwen3_cuda_tts_mem    $qwen3_cuda_tts_swap    $qwen3_cuda_tts_cpu
fi

total_mem=$(( nginx_mem + postgres_mem + redis_mem + proxq_mem ))
[ "$flag_claudebox" = "1" ]   && total_mem=$(( total_mem + claudebox_mem ))
[ "$flag_cbzai" = "1" ]       && total_mem=$(( total_mem + cbzai_mem ))
[ "$flag_hybrids3" = "1" ]    && total_mem=$(( total_mem + hybrids3_mem ))
[ "$flag_speaches" = "1" ]    && total_mem=$(( total_mem + speaches_mem ))
[ "$flag_ollama" = "1" ]      && total_mem=$(( total_mem + ollama_mem ))
if [ "$flag_sdcpp" = "1" ]; then
    if [ "$flag_cuda" = "1" ]; then total_mem=$(( total_mem + sdcpp_cuda_mem ))
    else total_mem=$(( total_mem + sdcpp_mem )); fi
fi
[ "$flag_cloudflared" = "1" ] && total_mem=$(( total_mem + cloudflared_mem ))
[ "$flag_mcp" = "1" ]        && total_mem=$(( total_mem + mcp_mem ))
[ "$flag_librechat" = "1" ]  && total_mem=$(( total_mem + librechat_mem + librechat_mongo_mem ))
[ "$flag_browser" = "1" ]     && total_mem=$(( total_mem + sab_redis_mem + sab_mem * sab_replicas + sab_proxy_mem ))
[ "$flag_cuda" = "1" ]        && total_mem=$(( total_mem + ollama_cuda_mem + speaches_cuda_mem + qwen3_cuda_tts_mem ))

echo ""
echo "Total max RAM (all enabled persistent services): $(fmt $total_mem)"
echo "  ($(( total_mem * 100 / total_ram_mb ))% of total RAM, MAXUSE=${maxuse}%)"

# ── Write .env.limits ─────────────────────────────────────────────────────────

cat > "$OUT" << ENVEOF
# Auto-generated by: make limits
# System: ${total_ram_mb}MB RAM, ${total_swap_mb}MB swap, ${total_cores} cores (MAXUSE=${maxuse}%)
# Enabled: cuda=${flag_cuda} speaches=${flag_speaches} ollama=${flag_ollama} sdcpp=${flag_sdcpp} browser=${flag_browser} claudebox=${flag_claudebox} cbzai=${flag_cbzai} hybrids3=${flag_hybrids3} cloudflared=${flag_cloudflared} librechat=${flag_librechat} mcp=${flag_mcp}
# Scale: ${scale}% — re-run make limits after enabling/disabling services
# Regenerate: make limits  or  MAXUSE=80 make limits

NGINX_AUTH_INIT_MEM_LIMIT=$(fmt $nginx_init_mem)
NGINX_AUTH_INIT_MEMSWAP_LIMIT=$(fmt $nginx_init_swap)
NGINX_AUTH_INIT_CPUS=${nginx_init_cpu}

NGINX_MEM_LIMIT=$(fmt $nginx_mem)
NGINX_MEMSWAP_LIMIT=$(fmt $nginx_swap)
NGINX_CPUS=${nginx_cpu}

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

PROXQ_MEM_LIMIT=$(fmt $proxq_mem)
PROXQ_MEMSWAP_LIMIT=$(fmt $proxq_swap)
PROXQ_CPUS=${proxq_cpu}

MCP_MEM_LIMIT=$(fmt $mcp_mem)
MCP_MEMSWAP_LIMIT=$(fmt $mcp_swap)
MCP_CPUS=${mcp_cpu}

LIBRECHAT_MEM_LIMIT=$(fmt $librechat_mem)
LIBRECHAT_MEMSWAP_LIMIT=$(fmt $librechat_swap)
LIBRECHAT_CPUS=${librechat_cpu}

LIBRECHAT_MONGO_MEM_LIMIT=$(fmt $librechat_mongo_mem)
LIBRECHAT_MONGO_MEMSWAP_LIMIT=$(fmt $librechat_mongo_swap)
LIBRECHAT_MONGO_CPUS=${librechat_mongo_cpu}

SDCPP_MEM_LIMIT=$(fmt $sdcpp_mem)
SDCPP_MEMSWAP_LIMIT=$(fmt $sdcpp_swap)
SDCPP_CPUS=${sdcpp_cpu}

SDCPP_PULL_MEM_LIMIT=$(fmt $sdcpp_pull_mem)
SDCPP_PULL_MEMSWAP_LIMIT=$(fmt $sdcpp_pull_swap)
SDCPP_PULL_CPUS=${sdcpp_pull_cpu}

SDCPP_CUDA_MEM_LIMIT=$(fmt $sdcpp_cuda_mem)
SDCPP_CUDA_MEMSWAP_LIMIT=$(fmt $sdcpp_cuda_swap)
SDCPP_CUDA_CPUS=${sdcpp_cuda_cpu}

OLLAMA_CUDA_MEM_LIMIT=$(fmt $ollama_cuda_mem)
OLLAMA_CUDA_MEMSWAP_LIMIT=$(fmt $ollama_cuda_swap)
OLLAMA_CUDA_CPUS=${ollama_cuda_cpu}

SPEACHES_CUDA_MEM_LIMIT=$(fmt $speaches_cuda_mem)
SPEACHES_CUDA_MEMSWAP_LIMIT=$(fmt $speaches_cuda_swap)
SPEACHES_CUDA_CPUS=${speaches_cuda_cpu}

QWEN3_CUDA_TTS_MEM_LIMIT=$(fmt $qwen3_cuda_tts_mem)
QWEN3_CUDA_TTS_MEMSWAP_LIMIT=$(fmt $qwen3_cuda_tts_swap)
QWEN3_CUDA_TTS_CPUS=${qwen3_cuda_tts_cpu}
ENVEOF

echo ""
echo "Written to: $OUT"
echo "Review it, then restart: make restart"
echo ""
