require "spec"
require "../../../src/pty"

describe PTY::Command do
  # Interactive tools inspect all three standard descriptors; each must point to
  # the PTY or they may choose non-interactive behavior or fail to launch correctly.
  it "connects stdin, stdout and stderr to the PTY" do
    command = PTY::Command.new("if [ -t 0 ] && [ -t 1 ] && [ -t 2 ]; then printf pty-is-a-terminal; else printf not-a-terminal; fi")

    output, exit_code = command.execute_inside_pty { |_chunk| }

    output.should contain("pty-is-a-terminal")
    exit_code.should eq(0)
  end
end
