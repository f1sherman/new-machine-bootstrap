# Shared runtime. Package downloads happen at build time, not during trials.
FROM node:22-bookworm-slim@sha256:e9f565d32859f0cbfb52125eafe8be39390f24dac302dc3cdf566e8ba3ab21ee
ARG PI_VERSION=1.5.2
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl git jq python3 ruby \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g --ignore-scripts @earendil-works/pi-coding-agent@${PI_VERSION} \
    && useradd --uid 1001 --create-home --shell /bin/bash worker \
    && mkdir -p /home/worker/.nvm /workspace \
    && printf ':\n' > /home/worker/.nvm/nvm.sh \
    && chown -R worker:worker /home/worker /workspace
ENV HOME=/home/worker PI_TELEMETRY=0 PI_SKIP_VERSION_CHECK=1
WORKDIR /workspace
CMD ["sleep", "infinity"]
