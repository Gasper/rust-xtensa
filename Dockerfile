FROM ubuntu:bionic AS esp-tools-stage

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates git wget libncurses-dev flex bison \
        gperf python python-pip python-setuptools cmake \
        ninja-build ccache libffi-dev libssl-dev

WORKDIR /tmp/
RUN git clone -b v4.0.1 --recursive --depth 1 https://github.com/espressif/esp-idf.git
WORKDIR /tmp/esp-idf/
RUN ./install.sh


FROM ubuntu:bionic AS compiler-stage

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

# Install prerequisites
RUN set -eux
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        automake bison \
        ca-certificates curl cmake \
        flex \
        gcc g++ gawk gperf grep gettext git \
        help2man \
        libc6-dev libtool libtool-bin \
        make \
        python2.7 python2.7-dev \
        texinfo \
        wget        

# Install rustup
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --no-modify-path --profile minimal
RUN chmod -R a+w $RUSTUP_HOME $CARGO_HOME

# Build rustc compiler with Xtensa support
WORKDIR /tmp/rust-xtensa/
COPY src /tmp/rust-xtensa/
COPY Cargo.lock Cargo.toml configure x.py /tmp/rust-xtensa/
RUN ./configure --experimental-targets=Xtensa
RUN python2.7 ./x.py build

# Install xargo
RUN cargo install xargo


FROM ubuntu:bionic AS final-stage

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=$PATH:/usr/local/cargo/bin

# Install prerequisites
RUN set -eux
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates \
        # For openocd
        libusb-1.0 \
        # For compiler_builtins
        gcc libc6-dev

# Copy built cargo and rustup
WORKDIR /usr/local
COPY --from=compiler-stage /usr/local/rustup/ rustup
COPY --from=compiler-stage /usr/local/cargo/ cargo

# Copy rustc compiler and its source
WORKDIR /usr/local/rust-xtensa/
COPY --from=compiler-stage /tmp/rust-xtensa/build/x86_64-unknown-linux-gnu/stage2/bin bin
COPY --from=compiler-stage /tmp/rust-xtensa/build/x86_64-unknown-linux-gnu/stage2/lib lib
COPY --from=compiler-stage /tmp/rust-xtensa/src/liballoc src/liballoc
COPY --from=compiler-stage /tmp/rust-xtensa/src/libcore src/libcore
COPY --from=compiler-stage /tmp/rust-xtensa/src/stdarch src/stdarch
COPY --from=compiler-stage /tmp/rust-xtensa/Cargo.lock .
COPY --from=compiler-stage /tmp/rust-xtensa/*.toml /usr/local/rust-xtensa/

# Copy ESP IDF tools
WORKDIR /usr/local/esp-idf/
COPY --from=esp-tools-stage /root/.espressif/tools/ .

# Envirnoment variables
ENV XARGO_RUST_SRC=/usr/local/rust-xtensa/src \
    RUSTC=/usr/local/rust-xtensa/bin/rustc \
    RUSTDOC=/usr/local/rust-xtensa/bin/rustdoc \
    PATH=$PATH:/usr/local/esp-idf/xtensa-esp32-elf/esp-2019r2-8.2.0/xtensa-esp32-elf/bin/

# Cleanup
RUN rm -rf /var/lib/apt/lists/*

# Move to workspace directory
WORKDIR /home/workspace

ENTRYPOINT [ "bash" ]
