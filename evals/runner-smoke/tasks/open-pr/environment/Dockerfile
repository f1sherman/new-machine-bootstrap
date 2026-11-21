FROM nmb-eval-runtime
COPY --chmod=755 fixture-pr /usr/local/bin/fixture-pr
COPY --chown=worker:worker open-pr /home/worker/.pi/agent/skills/open-pr
USER worker
RUN git init --bare /workspace/origin.git && git init -b main /workspace/project \
    && cd /workspace/project && git config user.name Fixture \
    && git config user.email fixture@example.invalid \
    && printf '# Delivery queue\n\nThe retry delay controls how long failed jobs wait.\n' > README.md \
    && printf 'retry_delay_seconds = 5\n' > delivery.toml \
    && git add . && git commit -m 'Configure delivery retries' \
    && git remote add origin /workspace/origin.git && git push origin main \
    && git switch -c longer-retry-delay \
    && printf 'retry_delay_seconds = 30\n' > delivery.toml \
    && git commit -am 'Increase delivery retry delay to 30 seconds' \
    && printf '[]\n' > /workspace/submissions.json
USER root
WORKDIR /workspace/project
