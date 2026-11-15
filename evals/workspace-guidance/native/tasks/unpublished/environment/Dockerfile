FROM nmb-eval-runtime
COPY repo-end repo-lib.sh /usr/local/bin/
RUN chmod 755 /usr/local/bin/repo-end /usr/local/bin/repo-lib.sh
COPY setup.sh /opt/workspace-setup.sh
RUN chmod 755 /opt/workspace-setup.sh
USER worker
RUN /opt/workspace-setup.sh
USER root
WORKDIR /workspace
