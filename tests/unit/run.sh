#!/bin/bash
# Runs the Python unit tests for the LiteLLM callbacks against a throwaway
# Redis that uses the ACL rendered from docker-compose.yml. Needs the
# aigate-litellm image (`docker compose build litellm`) but not a running stack.
# The Redis passwords are random per run and only exist for the test.
set -euo pipefail
trap 'printf "{\"level\":\"ERROR\",\"file\":\"run.sh\",\"line\":%d,\"msg\":\"command failed exit=%d\"}\n" "$LINENO" "$?" >&2' ERR

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
readonly REPO_DIR
readonly RUN_ID="$$"
readonly NETWORK="aigate-unit-net-${RUN_ID}"
readonly REDIS_CONTAINER="aigate-unit-redis-${RUN_ID}"
readonly RUNNER_CONTAINER="aigate-unit-runner-${RUN_ID}"
readonly REDIS_IMAGE="redis:7.4.9-alpine"
readonly LITELLM_IMAGE="${LITELLM_IMAGE:-aigate-litellm:latest}"
readonly WORK_DIR="${REPO_DIR}/.testing/unit"
readonly ACL_FILE="${WORK_DIR}/redis-${RUN_ID}.acl"
readonly LOG_FILE="${WORK_DIR}/run-${RUN_ID}.log"
readonly READY_ATTEMPTS=50
readonly READY_DELAY_SECONDS=0.2
readonly RANDOM_BYTES=12

mkdir -p "$WORK_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

log() {
    local level="$1"
    shift
    printf '{"time":"%s","level":"%s","file":"%s","line":%d,"func":"%s","msg":"%s"}\n' \
        "$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')" "$level" "${BASH_SOURCE[1]##*/}" \
        "${BASH_LINENO[0]}" "${FUNCNAME[1]:-main}" "$*" >&2
}

random_hex() {
    od -An -N"$RANDOM_BYTES" -tx1 /dev/urandom | tr -d ' \n'
}

cleanup() {
    if docker container inspect "$REDIS_CONTAINER" >/dev/null 2>&1; then
        docker stop "$REDIS_CONTAINER" >/dev/null
    fi
    if docker network inspect "$NETWORK" >/dev/null 2>&1; then
        docker network rm "$NETWORK" >/dev/null
    fi
    rm -f "$ACL_FILE"
}
trap cleanup EXIT

if ! docker image inspect "$LITELLM_IMAGE" >/dev/null 2>&1; then
    log ERROR "image ${LITELLM_IMAGE} missing, build it with: docker compose build litellm"
    exit 1
fi

TEST_PROXQ_REDIS_PASSWORD="proxq-$(random_hex)"
TEST_LITELLM_REDIS_PASSWORD="litellm-$(random_hex)"
readonly TEST_PROXQ_REDIS_PASSWORD TEST_LITELLM_REDIS_PASSWORD

REDIS_PASSWORD="$TEST_PROXQ_REDIS_PASSWORD" \
    LITELLM_REDIS_PASSWORD="$TEST_LITELLM_REDIS_PASSWORD" \
    docker compose -f "${REPO_DIR}/docker-compose.yml" --project-directory "$REPO_DIR" config \
    | docker run --rm -i --entrypoint /app/.venv/bin/python "$LITELLM_IMAGE" \
        -c 'import sys, yaml; sys.stdout.write(yaml.safe_load(sys.stdin)["configs"]["redis_acl"]["content"])' \
        >"$ACL_FILE"
log INFO "rendered redis ACL from docker-compose.yml"

docker network create "$NETWORK" >/dev/null
docker run -d --rm --name "$REDIS_CONTAINER" --network "$NETWORK" \
    -v "${ACL_FILE}:/etc/redis/users.acl:ro" \
    "$REDIS_IMAGE" redis-server --aclfile /etc/redis/users.acl >/dev/null

is_redis_ready() {
    # stderr is dropped on purpose: redis-cli prints connection errors while
    # the server is still starting, and the loop retries them.
    docker exec -e REDISCLI_AUTH="$TEST_PROXQ_REDIS_PASSWORD" "$REDIS_CONTAINER" \
        redis-cli --user proxq ping 2>/dev/null | grep -q PONG
}

for ((attempt = 1; attempt <= READY_ATTEMPTS; attempt++)); do
    if is_redis_ready; then
        break
    fi
    if ((attempt == READY_ATTEMPTS)); then
        log ERROR "redis did not become ready attempts=${READY_ATTEMPTS}"
        exit 1
    fi
    sleep "$READY_DELAY_SECONDS"
done
log INFO "redis ready, running unit tests"

docker run --rm --name "$RUNNER_CONTAINER" --network "$NETWORK" \
    -v "${REPO_DIR}/litellm/callbacks:/app/callbacks:ro" \
    -v "${REPO_DIR}/tests/unit:/unit-tests:ro" \
    -e PYTHONPATH=/app/callbacks \
    -e PYTHONDONTWRITEBYTECODE=1 \
    -e TEST_REDIS_HOST="$REDIS_CONTAINER" \
    -e TEST_PROXQ_REDIS_PASSWORD="$TEST_PROXQ_REDIS_PASSWORD" \
    -e TEST_LITELLM_REDIS_PASSWORD="$TEST_LITELLM_REDIS_PASSWORD" \
    --entrypoint /app/.venv/bin/python \
    "$LITELLM_IMAGE" -m unittest discover -s /unit-tests -p 'test_*.py' -v
log INFO "unit tests passed"
