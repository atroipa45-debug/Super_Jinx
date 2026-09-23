FROM ghcr.io/mhsanaei/3x-ui:v2.9.4

RUN apk add --no-cache nginx gettext bash curl jq coreutils

COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY start.sh /start.sh
COPY bootstrap.sh /bootstrap.sh
RUN chmod +x /start.sh /bootstrap.sh

ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["/start.sh"]
