# pop-fe image for linux/amd64 and linux/arm64.
#
# All compilers and headers stay in the build stage; the final image only
# carries the built tools, the Python environment and the runtime libraries.
#
#   docker build -t pop-fe .
#   docker run --rm -v /psx:/psx pop-fe --psp-dir=/psx/out /psx/game.cue
#
# pop-fe-docker.sh wraps this with input/output directory mounts.

FROM ghcr.io/astral-sh/uv:0.13.5 AS uv

FROM python:3.12-slim-bookworm AS build

ARG LCP_VERSION=v1.0.9

RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential cmake git ca-certificates libsndfile1-dev && \
  rm -rf /var/lib/apt/lists/*

COPY --from=uv /uv /usr/local/bin/uv

WORKDIR /pop-fe
COPY . .

# Python dependencies, pinned by uv.lock, against the image's own Python so
# the venv is valid in the runtime stage too.
ENV UV_PYTHON_DOWNLOADS=never UV_LINK_MODE=copy
RUN uv sync --frozen --python /usr/local/bin/python3 && \
  rm -f .python-version

# atracdenc: SND0 / CD-DA ATRAC3 encoder
RUN cd atracdenc/src && \
  cmake . -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 && \
  make -j"$(nproc)" atracdenc

# pkgcrypt: C extension used by PSL1GHT's pkg.py for PS3 packages
RUN cd PSL1GHT/tools/ps3py && PATH=/pop-fe/.venv/bin:$PATH make

# psx-undither
RUN cd psx-undither && make psxund

# libcrypt-patcher, built from source since upstream only ships x86 binaries
RUN git clone -q --depth 1 --branch ${LCP_VERSION} https://github.com/alex-free/libcrypt-patcher.git /tmp/lcp && \
  make -C /tmp/lcp lcp && \
  cp /tmp/lcp/build/lcp /pop-fe/lcp

# Drop build intermediates that pop-fe never reads. pop-fe writes its
# temporary files into the current directory, and the container may run as
# any user. Fixing permissions here rather than in the final stage avoids a
# second copy of the whole tree in another layer.
RUN rm -rf atracdenc/src/CMakeFiles atracdenc/src/*.a atracdenc/test \
  PSL1GHT/tools/ps3py/build psx-undither/build/*.o psx-undither/build/*.a && \
  mkdir -p pop-fe-work && chmod -R a+rwX /pop-fe


FROM python:3.12-slim-bookworm

# ffmpeg: audio conversion, mame-tools: chdman for CHD images,
# xdelta3: romhacks, unar: CBR manuals, wget: some asset downloads
RUN apt-get update && apt-get install -y --no-install-recommends \
  ffmpeg libsndfile1 mame-tools xdelta3 unar wget ca-certificates && \
  rm -rf /var/lib/apt/lists/*

COPY --from=build /pop-fe /pop-fe
# COPY keeps the modes of the contents but not of the target directory
# itself, which pop-fe also writes temporary files into.
RUN chmod a+rwx /pop-fe

ENV PATH=/pop-fe/.venv/bin:$PATH HOME=/tmp PYTHONUNBUFFERED=1
WORKDIR /pop-fe
ENTRYPOINT [ "python3", "./pop-fe.py" ]
