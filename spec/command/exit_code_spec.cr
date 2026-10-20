require "spec"
require "../../src/pty"

describe PTY::Command do
  # Consumers use the real exit code to decide whether a command succeeded;
  # returning zero for every completed child would hide shell command failures.
  it "returns the shell's real nonzero exit code" do
    command = PTY::Command.new("printf 'before-failure\\n'; exit 23")

    output, exit_code = command.execute_inside_pty { |_chunk| }

    output.should contain("before-failure")
    exit_code.should eq(23)
  end
end
