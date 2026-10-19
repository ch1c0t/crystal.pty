require "spec"
require "../../src/pty"

describe PTY::Command do
  # Omitting dimensions must still configure a PTY, rather than silently running
  # the command with stdin disconnected from a terminal.
  it "keeps stdin attached to a PTY when dimensions are omitted" do
    command = PTY::Command.new("if [ -t 0 ]; then printf terminal; fi")

    output, exit_code = command.execute_inside_pty { |_chunk| }

    output.should contain("terminal")
    exit_code.should eq(0)
  end
end
