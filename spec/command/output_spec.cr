require "spec"
require "../../src/pty"

describe "PTY::Command output" do
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

  it "drains output larger than a PTY buffer while the child runs" do
    command = PTY::Command.new("yes pty-output | head -c 131072")
    chunks = [] of String

    output, exit_code = command.execute_inside_pty do |chunk|
      chunks << chunk
    end

    output.bytesize.should be >= 131_072
    chunks.join.should eq(output)
    exit_code.should eq(0)
  end
end
