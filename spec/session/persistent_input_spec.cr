require "spec"
require "../../src/pty"

describe PTY::Session do
  # Separate writes must reach one surviving shell; otherwise environment and
  # working-directory state would be lost between interaction steps.
  it "preserves process state across repeated writes" do
    session = PTY::Session.new(["/bin/sh", "-i"])
    session.start
    session.write("export SESSION_VALUE=persistent\n")
    session.write("printf 'session-value:%s\\n' \"$SESSION_VALUE\"\n")
    session.write("exit 0\n")

    session.wait.should eq(0)
    session.output.should contain("session-value:persistent")
  end
end
