require "spec"
require "../../src/pty"

describe "PTY::Command exit" do
  it "returns the shell's real nonzero exit code" do
    command = PTY::Command.new("printf 'before-failure\\n'; exit 23", 1, Process.pid.to_i64)

    output, exit_code = command.execute_inside_pty { |_chunk| }

    output.should contain("before-failure")
    exit_code.should eq(23)
  end

  it "connects stdin, stdout and stderr to the PTY" do
    command = PTY::Command.new("if [ -t 0 ] && [ -t 1 ] && [ -t 2 ]; then printf pty-is-a-terminal; else printf not-a-terminal; fi")

    output, exit_code = command.execute_inside_pty { |_chunk| }

    output.should contain("pty-is-a-terminal")
    exit_code.should eq(0)
  end

  it "reports a command terminated by a signal using shell-compatible status" do
    command = PTY::Command.new(["/bin/sh", "-c", "kill -TERM $$"])

    _output, exit_code = command.execute_inside_pty { |_chunk| }

    exit_code.should eq(143)
  end

  it "returns 127 when an argv executable cannot be started" do
    command = PTY::Command.new(["/definitely/not/a/real/executable"])

    _output, exit_code = command.execute_inside_pty { |_chunk| }

    exit_code.should eq(127)
  end
end
