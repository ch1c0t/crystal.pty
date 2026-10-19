require "spec"
require "../../src/pty"

describe PTY::Command do
  # Shell callers expect 128 + signal number for signal termination; this protects
  # the status conversion from treating a signalled child like a normal exit.
  it "reports a command terminated by a signal using shell-compatible status" do
    command = PTY::Command.new(["/bin/sh", "-c", "kill -TERM $$"])

    _output, exit_code = command.execute_inside_pty { |_chunk| }

    exit_code.should eq(143)
  end
end
