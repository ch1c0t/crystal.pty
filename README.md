# crystal.pty

A Linux PTY library for Crystal. It supports one-shot commands as well as long-lived sessions that keep the same pseudo-terminal open across multiple input writes.

## Interactive sessions

Use `PTY::Session` when a process should stay attached to one PTY while you interact with it repeatedly:

```crystal
session = PTY::Session.new(["/bin/sh", "-i"], rows: 40, columns: 120)
session.start do |chunk|
  print chunk
end

session.write("export PTY_SESSION_VALUE=kept\\n")
session.write("printf '%s\\n' \"$PTY_SESSION_VALUE\"\\n")
session.write("exit\\n")
exit_code = session.wait
```

`start` launches the process and returns without waiting for it to exit. The optional callback receives output chunks as they arrive; the complete transcript is available through `session.output`. Call `write` as often as needed to send input to the same terminal. `resize(rows:, columns:)` changes the PTY window size. `alive?` checks whether the command leader is still running, `wait` returns its exit status, and `terminate` or `close` terminates the process group and waits for cleanup.

A PTY is one continuous terminal byte stream. It does not inherently tell you which output belongs to a particular command or when a command sent to an interactive shell has finished; applications that need per-command completion should use their own markers or protocol.

## One-shot API used by tmux.run

`PTY::Command` remains the backwards-compatible one-shot API. Its three-argument constructor and streaming callback are preserved:

```crystal
command = PTY::Command.new(command_string, index, run_id)
output, exit_code = command.execute_inside_pty do |chunk|
  output_sink.write(chunk)
end
```

The implementation now uses `PTY::Session` internally, then waits for completion and returns the accumulated terminal transcript and exit status. Existing consumers do not need to change.

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

When both `rows` and `columns` are supplied, they configure the PTY window size. When omitted, the native `openpty` default is preserved:

```crystal
output, exit_code = PTY.run("stty size", rows: 40, columns: 120)
```

## Reliability contract

- Child launch uses `openpty`, `fork`, `login_tty` and a shell wrapper that writes command status to a unique temporary file using atomic rename. Child-side launch failures terminate through `_exit(127)`.
- A blocking PTY reader drains output concurrently, preserving the combined stdout/stderr terminal stream.
- Linux PTY `EIO` on final slave closure is treated as end-of-stream.
- If descendants keep the slave terminal open after command status is reported, the session allows up to two seconds for natural EOF, then sends SIGHUP and SIGKILL to the command process group.
- Callback exceptions terminate the process group, clean up the reader and PTY, and are re-raised.
- stdin, stdout and stderr are attached to the controlling PTY. If `TERM` is unset, it defaults to `xterm-256color` in the child.

## Development

```sh
bundle install
bundle exec rake
crystal spec
bundle exec rspec
```

GitHub Actions regenerates sources, builds the CLI target, verifies generated-source consistency, and runs the PTY regression suite plus Ruby CLI smoke tests on Crystal 1.22.
