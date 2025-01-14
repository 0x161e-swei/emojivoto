# syntax=docker/dockerfile:experimental

FROM alpine/git:latest AS pull
RUN git clone https://github.com/0x161e-swei/emojivoto.git /emojivoto

FROM ghcr.io/edgelesssys/ego-deploy:latest AS emoji_base
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl dnsutils iptables jq nghttp2 && \
    apt clean && \
    apt autoclean

FROM ghcr.io/edgelesssys/ego-dev:latest AS emoji_build
RUN go get github.com/golang/protobuf/protoc-gen-go && \
    go get google.golang.org/grpc/cmd/protoc-gen-go-grpc
WORKDIR /node
RUN curl -sL https://deb.nodesource.com/setup_10.x -o nodesource_setup.sh && \
    bash nodesource_setup.sh
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - && \
    echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list
RUN apt update && \
    apt install -y yarn nodejs
COPY --from=pull /emojivoto /emojivoto
WORKDIR /emojivoto
RUN --mount=type=secret,id=signingkey,dst=/emojivoto/emojivoto-web/private.pem,required=true \
    --mount=type=secret,id=signingkey,dst=/emojivoto/emojivoto-emoji-svc/private.pem,required=true \
    --mount=type=secret,id=signingkey,dst=/emojivoto/emojivoto-voting-svc/private.pem,required=true \
    ego env make build
RUN curl -sL https://github.com/edgelesssys/edgelessrt/releases/download/v0.2.3/edgelessrt_0.2.3_amd64.deb -o edgelessrt.deb &&\
    apt install ./edgelessrt.deb build-essential libssl-dev
RUN source /opt/edgelessrt/share/openenclave/openenclaverc && \
    oesign eradump -e /emojivoto/emojivoto-voting-svc/target/emojivoto-voting-svc && \
    oesign eradump -e /emojivoto/emojivoto-emoji-svc/target/emojivoto-emoji-svc && \
    oesign eradump -e /emojivoto/emojivoto-web/target/emojivoto-web

FROM ghcr.io/edgelesssys/ego-dev:latest AS patch_build
RUN go get github.com/golang/protobuf/protoc-gen-go && \
    go get google.golang.org/grpc/cmd/protoc-gen-go-grpc
COPY --from=pull /emojivoto /emojivoto
WORKDIR /emojivoto
RUN --mount=type=secret,id=signingkey,dst=/emojivoto/emojivoto-voting-svc/private.pem,required=true \
    ego env make patch

FROM emoji_base AS release_emoji_svc
LABEL description="/emojivoto-emoji-svc"
COPY --from=emoji_build /emojivoto/emojivoto-emoji-svc/target/emojivoto-emoji-svc /emojivoto-emoji-svc
ENTRYPOINT ["ego", "marblerun", "/emojivoto-emoji-svc"]

FROM emoji_base AS release_voting_svc
LABEL description="emojivoto-voting-svc"
COPY --from=emoji_build /emojivoto/emojivoto-voting-svc/target/emojivoto-voting-svc /emojivoto-voting-svc
ENTRYPOINT ["ego", "marblerun", "/emojivoto-voting-svc"]

FROM emoji_base AS release_voting_update
LABEL description="emojivoto-voting-update"
COPY --from=patch_build /emojivoto/emojivoto-voting-svc/target/emojivoto-voting-svc /emojivoto-voting-svc
ENTRYPOINT ["ego", "marblerun", "/emojivoto-voting-svc"]

FROM emoji_base AS release_web
LABEL description="emojivoto-web"
COPY --from=emoji_build /emojivoto/emojivoto-web/target/emojivoto-web /emojivoto-web
COPY --from=emoji_build /emojivoto/emojivoto-web/target/web /web
COPY --from=emoji_build /emojivoto/emojivoto-web/target/dist /dist
COPY --from=emoji_build /emojivoto/emojivoto-web/target/emojivoto-vote-bot /emojivoto-vote-bot
ENTRYPOINT ["ego", "marblerun", "/emojivoto-web"]
