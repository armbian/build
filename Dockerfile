FROM ubuntu:16.04
RUN apt-get update
RUN apt-get install -y git build-essential binutils
WORKDIR /root
RUN git clone https://github.com/armbian/build/
RUN cp build/compile.sh .
