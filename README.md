# crystal.pty

A Linux PTY command runner for Crystal. It allocates a pseudo-terminal, attaches a child process to it, streams terminal output and returns the child's exit status.

## Existing API used by tmux.run

The three-argument constructor remains source-compatible:

```crystal
command = PTY::Command.new(command_string, index, run_id)
output, exit_code = command.execute_inside_pty do |chunk|
  output_sink.write(chunk)
end
```

`output` is the captured terminal transcript; `exit_code` is the normal exit code, or `128 + signal number` when the child was terminated by a signal. The callback receives each chunk as it is read. PTY output is a single combined terminal stream, not separate stdout and stderr streams.

The legacy `index` and `run_id` arguments remain accepted, but are no longer used to create temporary status files.

## One-shot API

Prefer an argv array when shell parsing is not required:

```crystal
output, exit_code = PTY.run(["/usr/bin/printf", "hello\\n"]) do |chunk|
  print chunk
end
```

Use a shell string only when shell syntax is intended:

```crystal
output, exit_code = PTY.run("printf 'hello\\n'; exit 3")
```

The terminal size defaults to 24 rows by 80 columns and can be customized:

```crystal
output, exit_code = PTY.run("stty size", rows: 40, columns: 120)
```

The transcript preserves terminal control characters and line endings. Apply ANSI stripping or presentation transformations in the consumer.

## Reliability contract

- Child status is obtained through Crystal's process-wait API; no status files are created.
- Output is drained concurrently with process monitoring, preventing large terminal output from deadlocking against a full PTY buffer.
- PTY read errors during terminal shutdown are treated as end-of-stream.
- If the main command exits while descendants still hold the terminal open, the process group receives SIGHUP and then SIGKILL after a short grace period.
- Callback exceptions terminate the child process group, wait for cleanup, and are re-raised.
- stdin, stdout and stderr are attached to the PTY. The child inherits its environment; if `TERM` is unset, it defaults to `xterm-256color` for the command.

This is a one-shot runner, not a general long-lived interactive-session API with explicit input forwarding and dynamic window resizing.

## Development

```sh
bundle install
bundle exec rake
crystal spec
bundle exec rspec
```

GitHub Actions regenerates the sources, builds the CLI target, verifies generated-source consistency (ignoring formatting-only differences), and runs Crystal lifecycle specs plus the Ruby CLI smoke test on Linux.
