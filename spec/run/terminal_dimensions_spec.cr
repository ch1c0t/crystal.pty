require "spec"
require "../../src/pty"

describe PTY do
  it "runs a string command with terminal dimensions" do
    output, exit_code = PTY.run("printf direct-string", rows: 30, columns: 100)

    output.should contain("direct-string")
    exit_code.should eq(0)
  end
end
