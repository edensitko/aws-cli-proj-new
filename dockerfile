FROM amazonlinux:2

RUN yum update -y && \
    yum install -y python3 unzip dos2unix which && \
    pip3 install --no-cache-dir awscli

COPY setup_red_blue_nginx.sh /setup.sh

RUN ls -l /setup.sh || (echo "ERROR: File not found!"; exit 1)

RUN dos2unix /setup.sh

RUN chmod +x /setup.sh

ENTRYPOINT ["/bin/bash", "-c", "/setup.sh"]
