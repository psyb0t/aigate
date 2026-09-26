FROM golang:1.26-bookworm@sha256:a688600ca24f8a4d3ca77f95b0dd40704a9fc787c826660eb7ba0b641b8b175d AS wrapper-build
WORKDIR /src
COPY wrapper/go.mod wrapper/go.sum ./
RUN go mod download
COPY wrapper/ ./
RUN CGO_ENABLED=0 go build -o /sdcpp-wrapper ./cmd

FROM ubuntu:24.04@sha256:008173c23f95b170204355c12626cb5a965d779a7e1283b09e9cffbb1bf33ca3 AS sdcpp-build
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

FROM ubuntu:24.04@sha256:008173c23f95b170204355c12626cb5a965d779a7e1283b09e9cffbb1bf33ca3
RUN apt-get update && \
    apt-get install -y --no-install-recommends libgomp1 && \
    rm -rf /var/lib/apt/lists/*
COPY --from=sdcpp-build /sd.cpp/build/bin/sd-server /sd-server
COPY --from=wrapper-build /sdcpp-wrapper /sdcpp-wrapper
COPY models-cpu.json /etc/sdcpp/models.json
ENTRYPOINT ["/sdcpp-wrapper"]
