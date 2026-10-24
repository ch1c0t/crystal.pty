require "spec"
require "../../src/pty"

describe PTY do
  it "runs a shell command through PTY.run" do
    output, exit_code = PTY.run("/bin/sh -c 'printf direct-argv'")

    output.should contain("direct-argv")
    exit_code.should eq(0)
  end
end
