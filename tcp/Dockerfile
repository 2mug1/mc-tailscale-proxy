FROM haproxy:lts

USER root

RUN apt-get update
RUN apt-get install wget curl iputils-ping net-tools -y
RUN apt-get install libcap2-bin -y
RUN setcap 'cap_net_bind_service=+ep' /usr/local/sbin/haproxy

USER haproxy
COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg