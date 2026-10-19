# crystal.pty

A Linux PTY command runner for Crystal. It allocates a pseudo-terminal, forks a child, makes the PTY slave the child's controlling terminal, streams terminal output and returns the child's exit status.

## Existing API used by tmux.run

The three-argument constructor and streaming callback are preserved:

```crystal
command = PTY::Command.new(command_string, index, run_id)
output, exit_code = command.execute_inside_pty do |chunk|
  output_sink.write(chunk)
end
```

`output` is the captured terminal transcript; `exit_code` is the normal exit code, or `128 + signal number` when the child was terminated by a signal. The callback receives each chunk as it is read. PTY output is a single combined terminal stream, not separate stdout and stderr streams.

The `index` and `run_id` parameters are retained for source compatibility. Exit status is collected from the child with `waitpid`, not a status file.

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
- The parent closes its copy of the slave PTY and drains output concurrently with nonblocking `waitpid` polling, preventing large output from filling the terminal buffer.
- Linux PTY `EIO` on final slave closure is treated as end-of-stream.
- If the main command exits while descendants still hold the terminal open, the process group receives SIGHUP and then SIGKILL after a short grace period.
- Callback exceptions terminate the command process group, wait for cleanup, and are re-raised.
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
