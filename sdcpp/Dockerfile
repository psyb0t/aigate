FROM golang:1.26-bookworm AS wrapper-build
WORKDIR /src
COPY wrapper/go.mod wrapper/go.sum ./
RUN go mod download
COPY wrapper/ ./
RUN CGO_ENABLED=0 go build -o /sdcpp-wrapper ./cmd

FROM ubuntu:24.04 AS sdcpp-build
RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential git cmake ca-certificates && \
    rm -rf /var/lib/apt/lists/*

ARG SDCPP_COMMIT=c97702e1057c2fe13a7074cd9069cb9dd6edc1bf
WORKDIR /sd.cpp
RUN git clone https://github.com/leejet/stable-diffusion.cpp . && \
    git checkout ${SDCPP_COMMIT} && \
    git submodule update --init --recursive

RUN cmake . -B ./build && \
    cmake --build ./build --config Release -j$(nproc)

FROM ubuntu:24.04
RUN apt-get update && \
    apt-get install -y --no-install-recommends libgomp1 && \
    rm -rf /var/lib/apt/lists/*
COPY --from=sdcpp-build /sd.cpp/build/bin/sd-server /sd-server
COPY --from=wrapper-build /sdcpp-wrapper /sdcpp-wrapper
COPY models-cpu.json /etc/sdcpp/models.json
ENTRYPOINT ["/sdcpp-wrapper"]
