require "spec"
require "../src/pty"

describe PTY::Command do
  it "preserves the tmux.run constructor and streams its terminal output" do
    chunks = [] of String
    command = PTY::Command.new("printf 'streamed-pty-output\\n'", 0, Process.pid.to_i64)

    output, exit_code = command.execute_inside_pty do |chunk|
      chunks << chunk
    end

    output.gsub("\r\n", "\n").should contain("streamed-pty-output\n")
    chunks.join.should eq(output)
    exit_code.should eq(0)
  end

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

  it "preserves the native PTY size when no dimensions are supplied" do
    command = PTY::Command.new("if [ -t 0 ]; then printf terminal; fi")

    output, exit_code = command.execute_inside_pty { |_chunk| }

    output.should contain("terminal")
    exit_code.should eq(0)
  end

  it "supports caller-specified terminal dimensions" do
    command = PTY::Command.new("stty size", rows: 42, columns: 120)

    output, exit_code = command.execute_inside_pty { |_chunk| }

    output.should contain("42 120")
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
    started_at = Time.monotonic

    output, exit_code = command.execute_inside_pty { |_chunk| }

    (Time.monotonic - started_at).should be < 3.seconds
    output.should contain("leader-exited")
    exit_code.should eq(0)
  end

  it "reports signal termination using the shell-compatible exit code" do
    _output, exit_code = PTY::Command.new("kill -TERM $$").execute_inside_pty { |_chunk| }

    exit_code.should eq(143)
  end

  it "returns 127 when an argv executable cannot be started" do
    command = PTY::Command.new(["/definitely/not/a/real/executable"])

    _output, exit_code = command.execute_inside_pty { |_chunk| }

    exit_code.should eq(127)
  end

  it "validates argv and terminal dimensions" do
    expect_raises(ArgumentError, "PTY command must not be empty") do
      PTY::Command.new([] of String)
    end
    expect_raises(ArgumentError, "PTY rows and columns must be provided together") do
      PTY::Command.new("true", rows: 30)
    end
    expect_raises(ArgumentError, "PTY rows must be between 1 and 65535") do
      PTY::Command.new("true", rows: 0, columns: 80)
    end
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

  it "streams data through the one-shot shell API" do
    chunks = [] of String
    output, exit_code = PTY.run("printf 'one-shot-stream'", rows: 30, columns: 100) do |chunk|
      chunks << chunk
    end

    output.should eq(chunks.join)
    exit_code.should eq(0)
  end
end
