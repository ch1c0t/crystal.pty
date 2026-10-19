# Use the platform process abstraction so Crystal owns and reaps the child.
# setsid creates a dedicated process group and -c makes the PTY its controlling
# terminal, allowing cleanup even if the command starts background descendants.
private def launch_process(slave_io : IO::FileDescriptor) : Process
  command = if argv = @argv
              argv
            else
              ["/bin/sh", "-c", @raw_string]
            end
  Process.new(["setsid", "-c"] + command, input: slave_io, output: slave_io, error: slave_io)
end
