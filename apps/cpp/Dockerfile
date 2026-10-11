FROM ubuntu:24.04 AS build
RUN apt-get update && apt-get install -y --no-install-recommends build-essential cmake git libasio-dev nlohmann-json3-dev ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY CMakeLists.txt app.cpp ./
RUN cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build --parallel 2

FROM ubuntu:24.04
COPY --from=build /src/build/backend-bench-cpp /usr/local/bin/backend-bench-cpp
EXPOSE 10000
CMD ["/usr/local/bin/backend-bench-cpp"]
