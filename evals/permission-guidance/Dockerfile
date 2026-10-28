FROM node:22-bookworm-slim@sha256:43ac6c60b8f89723f746e8a92ce91abd5017e627ce1ddfe4238355d3a30b772c
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git python3 procps \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /workspace
COPY project/ /workspace/
COPY AGENTS.md /root/.pi/agent/AGENTS.md
COPY snapshots.mjs /root/.pi/agent/extensions/permission.js
COPY watched.json /opt/eval/watched.json
RUN chmod +x bin/* && git init -q -b eval/permission \
    && git -c user.name=Fixture -c user.email=fixture@example.invalid add . \
    && git -c user.name=Fixture -c user.email=fixture@example.invalid \
       commit -qm 'Permission workflow fixture'
