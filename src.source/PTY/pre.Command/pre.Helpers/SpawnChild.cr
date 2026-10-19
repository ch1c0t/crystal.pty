# setsid creates a dedicated process group; -c makes the PTY the controlling
# terminal. A separate group lets the parent clean up descendants on exit.
private def launch_process(slave_io : IO::FileDescriptor) : Process
  command = if argv = @argv
              argv
            else
              ["/bin/sh", "-c", @raw_string]
            end
  environment = {"TERM" => (ENV["TERM"]? || "xterm-256color")} of String => String?
  Process.new("setsid", ["-c", "--"] + command, env: environment, input: slave_io, output: slave_io, error: slave_io)
end
