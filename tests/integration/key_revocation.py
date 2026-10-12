"""Live cross-worker key revocation without an inference request."""

import json
import os
import time
import uuid
from urllib.error import HTTPError
from urllib.request import Request, urlopen


def request(base_url, path, token, body=None):
    data = None if body is None else json.dumps(body).encode()
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    call = Request(base_url + path, data=data, headers=headers)
    try:
        with urlopen(call, timeout=30) as response:
            return response.status, json.loads(response.read())
    except HTTPError as error:
        return error.code, None


def main():
    base_url = os.environ["BASE_URL"].rstrip("/")
    master_key = os.environ["LITELLM_MASTER_KEY"]
    status, created = request(
        base_url,
        "/key/generate",
        master_key,
        {
            "duration": "5m",
            "models": ["groq-gpt-oss-20b"],
            "key_alias": "auth-revocation-test-" + uuid.uuid4().hex,
        },
    )
    if status != 200 or not isinstance(created, dict) or not created.get("key"):
        raise RuntimeError(f"test key generation failed: HTTP {status}")
    key = created["key"]
    deleted = False
    try:
        for _ in range(24):
            status, _ = request(base_url, "/models", key)
            if status != 200:
                raise RuntimeError(f"test key warm-up failed: HTTP {status}")
        status, _ = request(base_url, "/key/delete", master_key, {"keys": [key]})
        if status != 200:
            raise RuntimeError(f"test key deletion failed: HTTP {status}")
        deleted = True
        time.sleep(0.5)
        statuses = [request(base_url, "/models", key)[0] for _ in range(24)]
        if statuses != [401] * len(statuses):
            raise RuntimeError(f"revoked key accepted by a worker: statuses={statuses}")
        print(
            "OK: 24 authenticated warm-ups, then 24 rejected calls after key revocation"
        )
    finally:
        if not deleted:
            status, _ = request(base_url, "/key/delete", master_key, {"keys": [key]})
            if status != 200:
                raise RuntimeError(f"test key cleanup failed: HTTP {status}")


if __name__ == "__main__":
    main()
