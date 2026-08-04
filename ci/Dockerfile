FROM mstorsjo/llvm-mingw:20260616

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        make \
        nsis \
        osslsigncode \
        zip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
