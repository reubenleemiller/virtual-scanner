FROM mstorsjo/llvm-mingw:20260616

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        make \
        nsis \
        osslsigncode \
        p7zip-full \
        python3 \
        zip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
