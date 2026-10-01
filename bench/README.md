# Benchmarks

`bench_wbtest.mbt` mirrors upstream's `benchmarks/benches/templates.rs`;
`micro_wbtest.mbt` contains micro benchmarks for single instructions.

```bash
moon bench --target native --release bench
```

Reference numbers (Apple Silicon, native backend, release; upstream
measured with `cargo bench --bench templates` on the same machine):

| benchmark      | MiniJinja (Rust) | minijinja.mbt |
|----------------|-----------------:|--------------:|
| compile        |           8.4 µs |         37 µs |
| render         |            50 µs |         95 µs |
| loop_map_items |           3.0 ms |        3.4 ms |
| tuple_ops      |            49 µs |         76 µs |
