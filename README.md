# crystal.pty

A Linux PTY command runner for Crystal. The library allocates a pseudo-terminal, attaches a child process to it, streams terminal output, and returns the child's exit status.

## Existing API used by tmux.run

The current three-argument API remains supported:

```crystal
command = PTY::Command.new(command_string, index, run_id)
output, exit_code = command.execute_inside_pty do |chunk|
  output_sink.write(chunk)
end
```

`output` contains the captured terminal transcript; `exit_code` is the child's exit code, or `128 + signal` when it was terminated by a signal. The callback receives chunks as they are read. PTY output is a single combined terminal stream, not separate stdout and stderr streams.

The `index` and `run_id` constructor arguments are retained for compatibility; they are no longer used to create temporary status files. The child status comes from `waitpid`.

## Preferred API

Use an argument array to avoid shell parsing when a shell isn't needed:

```crystal
output, exit_code = PTY.run(["/usr/bin/printf", "hello\\n"]) do |chunk|
  print chunk
end
```

Use a shell string only when shell syntax is intended:

```crystal
output, exit_code = PTY.run("printf 'hello\\n'; exit 3")
```

The returned transcript preserves terminal control characters and line endings. Apply ANSI stripping or other presentation transformations in the consumer, not in this library.

## Reliability contract

- Child exit status is collected with `waitpid`; no temporary status files are created.
- Output is drained concurrently with process monitoring, preventing large terminal output from deadlocking against a full PTY buffer.
- PTY read errors at terminal shutdown are treated as end-of-stream.
- If the main command exits while descendants still hold the terminal open, the process group receives SIGHUP and then SIGKILL after a short grace period.
- Callback exceptions terminate the child process group, wait for cleanup, and are re-raised to the caller.
- Standard input, output and error are attached to the PTY. The default `TERM` is `xterm-256color` unless the child environment already defines it.

This runner is intended for one-shot commands. It is not yet a general long-lived interactive-session API with explicit input forwarding and dynamic window resizing.

## Development

```sh
bundle install
bundle exec rake
crystal spec
```

The GitHub Actions workflow runs source generation, builds the CLI target, and executes the PTY lifecycle regression specs on Linux.
