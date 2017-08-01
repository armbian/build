FROM ubuntu:16.04
RUN apt-get update
RUN apt-get install -y git build-essential binutils apt-cacher-ng
WORKDIR /root
RUN git clone https://github.com/igorpecovnik/lib/ --depth 1
RUN cp lib/compile.sh .
VOLUME ["root/compiled", "root/output"]
ENTRYPOINT ["./compile.sh"]
CMD ["BOARD=orangepipcplus", "PROGRESS_DISPLAY=plain", "RELEASE=jessie", "PROGRESS_LOG_TO_FILE=yes", "KERNEL_ONLY=no", "BUILD_DESKTOP=no", "BRANCH=default"]
