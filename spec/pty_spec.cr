require "spec"
require "../src/pty"

describe PTY::Command do
  it "preserves the tmux.run constructor and returns streamed output with the real exit code" do
    chunks = [] of String
    command = PTY::Command.new("printf 'streamed-pty-output\\n'", 0, Process.pid.to_i64)

    output, exit_code = command.execute_inside_pty do |chunk|
      chunks << chunk
    end

    output.should contain("streamed-pty-output")
    chunks.join.should contain("streamed-pty-output")
    exit_code.should eq(0)
  end

  it "returns a nonzero shell exit code without using a status file" do
    command = PTY::Command.new("printf 'before-failure\\n'; exit 23", 1, Process.pid.to_i64)

    output, exit_code = command.execute_inside_pty { |_chunk| }

    output.should contain("before-failure")
    exit_code.should eq(23)
  end

  it "connects all standard streams to a terminal" do
    command = PTY::Command.new("if [ -t 0 ] && [ -t 1 ] && [ -t 2 ]; then printf pty-is-a-terminal; else printf not-a-terminal; fi")

    output, exit_code = command.execute_inside_pty { |_chunk| }

    output.should contain("pty-is-a-terminal")
    exit_code.should eq(0)
  end

  it "drains output larger than a PTY buffer while the child runs" do
    command = PTY::Command.new("yes pty-output | head -c 131072")

    output, exit_code = command.execute_inside_pty { |_chunk| }

    output.bytesize.should be >= 131_072
    exit_code.should eq(0)
  end

  it "does not wait forever for descendants which inherit the PTY" do
    command = PTY::Command.new("sleep 30 </dev/tty >/dev/tty 2>&1 & printf leader-exited; exit 0")

    output, exit_code = command.execute_inside_pty { |_chunk| }

    output.should contain("leader-exited")
    exit_code.should eq(0)
  end

  it "returns 127 when an argv executable cannot be started" do
    command = PTY::Command.new(["/definitely/not/a/real/executable"])

    _output, exit_code = command.execute_inside_pty { |_chunk| }

    exit_code.should eq(127)
  end

  it "propagates stream callback errors after cleaning up the child" do
    command = PTY::Command.new("printf 'callback-error-test'; sleep 1")

    expect_raises(ArgumentError, "stream sink failed") do
      command.execute_inside_pty do |_chunk|
        raise ArgumentError.new("stream sink failed")
      end
    end
  end
end

describe PTY do
  it "offers the one-shot argv API" do
    output, exit_code = PTY.run(["/bin/sh", "-c", "printf direct-argv"])

    output.should contain("direct-argv")
    exit_code.should eq(0)
  end
end
