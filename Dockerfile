
# OWT development environment.
# @see https://github.com/open-webrtc-toolkit/owt-server/blob/master/docker/Dockerfile
# @see https://github.com/open-webrtc-toolkit/owt-server#how-to-build-release-package
# Ubuntu 18(Bionic Beaver)
FROM ubuntu:bionic

RUN apt-get update
RUN apt-get install -y aptitude gdb \
    ca-certificates git lsb-release mongodb nodejs npm sudo wget
RUN npm install -g grunt-cli node-gyp

ADD owt-client-javascript-4.3.tar.gz /tmp/git/owt-docker
RUN cd /tmp/git/owt-docker/owt-client-javascript-4.3/scripts && npm install && grunt
ENV CLIENT_SAMPLE_PATH=/tmp/git/owt-docker/owt-client-javascript-4.3/dist/samples/conference

ADD MediaStack-18.4.0.tar.gz /tmp/git/owt-docker
RUN cd /tmp/git/owt-docker/MediaStack && ./install_media.sh
ENV MFX_HOME=/opt/intel/mediasdk

# This is needed to patch licode
RUN  git config --global user.email "you@example.com" && \
  git config --global user.name "Your Name"

# @see https://blog.piasy.com/2019/04/14/OWT-Server-Quick-Start/index.html
ADD owt-server-4.3.tar.gz /tmp/git/owt-docker
RUN cd /tmp/git/owt-docker/owt-server-4.3 && ./scripts/installDepsUnattended.sh && \
    ./scripts/build.js -t all --check &&
    ./scripts/pack.js -t all --install-module --sample-path $CLIENT_SAMPLE_PATH

WORKDIR /tmp/git/owt-docker/owt-server-4.3
CMD ["pwd"]
