require "spec"
require "../../src/pty"

describe PTY::Command do
  # tmux.run depends on this positional constructor; the callback must receive
  # the same complete, ordered output that execute_inside_pty returns.
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
end
