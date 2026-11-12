kachi is the key-value database aiming to be compatible with RESP 3.

## Getting Started

the fastest way to get started:

```sh
git clone https://github.com/vdkenny/kachi.zig.git

zig run src/main.src
```

## Benchmarks

take these numbers with a grain of salt.

**valkey**:

```
Summary [GET Only]:
  throughput summary: 98667.98 requests per second
  latency summary (msec):
          avg       min       p50       p95       p99       max
        0.277     0.064     0.271     0.391     0.559     1.599
```

**kachi:**
```
Summary [GET Only]:
  throughput summary: 76929.00 requests per second
  latency summary (msec):
          avg       min       p50       p95       p99       max
        0.343     0.064     0.351     0.455     0.503     1.343
```

Hardware: WSL2 v6.18.58.1, Ryzen 7 9800X3D, 16GB DDR5 6000MHz CL30
