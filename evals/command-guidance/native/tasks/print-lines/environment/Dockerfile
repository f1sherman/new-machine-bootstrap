FROM nmb-eval-runtime
RUN apt-get update && apt-get install -y --no-install-recommends zsh \
    && rm -rf /var/lib/apt/lists/*
COPY capture.py /opt/command-stubs/capture.py
RUN chmod 755 /opt/command-stubs/capture.py \
    && for name in cat curl tool; do ln -s capture.py /opt/command-stubs/$name; done
WORKDIR /workspace
