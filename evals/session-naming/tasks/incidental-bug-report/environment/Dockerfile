FROM node:22-bookworm-slim@sha256:43ac6c60b8f89723f746e8a92ce91abd5017e627ce1ddfe4238355d3a30b772c
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git jq procps python3 ruby util-linux \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /workspace
COPY project/ /workspace/
COPY runtime/ /root/.pi/agent/extensions/
COPY AGENTS.md /root/.pi/agent/AGENTS.md
COPY managed-hooks.ts /opt/eval/managed-hooks.ts
COPY description.txt /opt/eval/description.txt
RUN chmod +x bin/* && mkdir -p .issues && printf '[]\n' > .issues/issues.json \
    && git init -q -b main \
    && git -c user.name=Fixture -c user.email=fixture@example.invalid \
       add . \
    && git -c user.name=Fixture -c user.email=fixture@example.invalid \
       commit -qm 'Public terminal helper snapshot'
