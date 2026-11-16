ARG TASK_IMAGE=nmb-eval-runtime
FROM ${TASK_IMAGE}
COPY tests/ /tests/
RUN mkdir -p /logs/verifier && chmod 700 /tests /logs /workspace
