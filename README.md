# crystal.pty

A Linux PTY command runner for Crystal. It allocates a pseudo-terminal, forks a child, makes the PTY slave the child's controlling terminal, streams terminal output and returns the command's exit status.

## Existing API used by tmux.run

The three-argument constructor and streaming callback are preserved:

```crystal
command = PTY::Command.new(command_string, index, run_id)
output, exit_code = command.execute_inside_pty do |chunk|
  output_sink.write(chunk)
end
```

`output` is the captured terminal transcript; `exit_code` is the normal exit code, or `128 + signal number` when a command is terminated by a signal. The callback receives each chunk as it is read. PTY output is a single combined terminal stream, not separate stdout and stderr streams.

The `index` and `run_id` parameters remain accepted for source compatibility. Each invocation uses a unique temporary status file, written to a temporary path and atomically renamed when the command status is ready. This avoids relying on `waitpid` when the host Crystal runtime may already have reaped the forked child.

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

When both `rows` and `columns` are supplied, they configure the PTY window size. If omitted, the native `openpty` default is preserved:

```crystal
output, exit_code = PTY.run("stty size", rows: 40, columns: 120)
```

## Reliability contract

- Child launch uses `openpty`, `fork`, `login_tty` and `exec`; child-side launch failures terminate through `_exit(127)`.
- The child reports its command status through a unique temporary file and an atomic rename.
- A blocking PTY reader drains output concurrently; the runner waits for natural PTY EOF after status is reported, preserving output already queued by the terminal.
- Linux PTY `EIO` on final slave closure is treated as end-of-stream.
- If descendants keep the slave terminal open after the command status is reported, the runner allows up to two seconds for natural EOF, then sends SIGHUP and SIGKILL to the command process group.
- Callback exceptions terminate the command process group, complete reader cleanup, and are re-raised.
- stdin, stdout and stderr are attached to the controlling PTY. The child inherits the environment; if `TERM` is unset, it defaults to `xterm-256color` in the child.

This is a one-shot runner, not a general long-lived interactive-session API with input forwarding and dynamic window resizing.

## Development

```sh
bundle install
bundle exec rake
crystal spec
bundle exec rspec
```

GitHub Actions regenerates the sources, builds the CLI target, verifies generated-source consistency (ignoring formatting-only differences), and runs the PTY lifecycle regression suite plus Ruby CLI smoke tests on Crystal 1.22.
