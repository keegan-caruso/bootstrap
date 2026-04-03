# hyperfine

`hyperfine` benchmarks shell commands.

## Common Commands

- `hyperfine 'rg foo' 'grep -R foo .'`: compare two commands
- `hyperfine 'npm test'`: benchmark one command
- `hyperfine --warmup 3 'cargo test'`: add warmup runs
