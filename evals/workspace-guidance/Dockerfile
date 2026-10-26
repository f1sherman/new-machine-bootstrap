FROM ruby:3.4-bookworm@sha256:9d1b22f2341dc96a1cd2f4f4495a31c19495b42ed243f1338e60075210025fd4
RUN apt-get update && apt-get install -y --no-install-recommends jq strace \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --uid 1000 --create-home eval
CMD ["sleep", "infinity"]
