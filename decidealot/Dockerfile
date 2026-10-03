# syntax=docker/dockerfile:1.7
ARG DECIDEALOT_IMAGE=psyb0t/decidealot:v0.6.0
FROM ${DECIDEALOT_IMAGE}
USER root
COPY --from=ghcr.io/astral-sh/uv:0.12.17@sha256:10787c682e4184e4f290de1171fd4703dc63de99221f10fe1c99002ce7fa9acc /uv /tmp/uv
COPY decidealot/requirements.txt /tmp/aigate-requirements.txt
RUN /tmp/uv pip install --python /opt/app-venv/bin/python --no-cache --require-hashes --no-deps -r /tmp/aigate-requirements.txt \
    && /opt/app-venv/bin/python -c 'import redis, jwt; assert redis.__version__ == "5.3.1"' \
    && rm /tmp/uv /tmp/aigate-requirements.txt
COPY litellm/callbacks/hardware_lock.py decidealot/coordinator.py decidealot/entrypoint.py /opt/aigate/
ENV PYTHONPATH=/opt/aigate
USER 1000:1000
ENTRYPOINT ["/opt/app-venv/bin/python", "/opt/aigate/entrypoint.py"]
