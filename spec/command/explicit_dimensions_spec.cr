require "spec"
require "../../src/pty"

describe PTY::Command do
  # Terminal applications read their size through the TTY; this catches regressions
  # where requested rows and columns are accepted but never applied to the PTY.
  it "supports caller-specified terminal dimensions" do
    command = PTY::Command.new("stty size", rows: 42, columns: 120)

    output, exit_code = command.execute_inside_pty { |_chunk| }

    output.should contain("42 120")
    exit_code.should eq(0)
  end
end
