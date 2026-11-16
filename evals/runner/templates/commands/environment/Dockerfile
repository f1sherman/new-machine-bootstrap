FROM nmb-eval-runtime
RUN apt-get update && apt-get install -y --no-install-recommends zsh \
    && rm -rf /var/lib/apt/lists/*
COPY . /workspace/
RUN mkdir -p /opt/command-stubs \
    && install -m 755 /workspace/capture.py /opt/command-stubs/capture.py \
    && rm /workspace/capture.py \
    && for name in cat curl tool; do ln -s capture.py /opt/command-stubs/$name; done \
    && ln -s /opt/command-stubs/capture.py /usr/local/bin/tool \
    && if [ -f /workspace/setup.sh ]; then bash /workspace/setup.sh; fi
WORKDIR /workspace
