require "spec"
require "../../../src/pty"

describe PTY::Command do
  # A failed exec must return a conventional shell status rather than hanging
  # the reader or accidentally reporting success.
  it "returns 127 when an argv executable cannot be started" do
    command = PTY::Command.new("/definitely/not/a/real/executable")

    _output, exit_code = command.execute_inside_pty { |_chunk| }

    exit_code.should eq(127)
  end
end
