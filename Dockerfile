FROM Ubuntu
RUN apt-get update
RUN apt-get install -y git
RUN git clone https://github.com/igorpecovnik/lib/
