require "spec"
require "../../src/pty"

describe PTY::Session do
  # Multiple input writes must reach one surviving process; the child reads
  # two separate lines and combines them, proving this is not a new PTY per write.
  it "preserves one process across repeated writes" do
    session = PTY::Session.new(["/bin/sh", "-c", "read first; read second; printf 'session-value:%s-%s\\n' \"$first\" \"$second\""])
    session.start
    session.write("persistent\n")
    session.write("state\n")

    session.wait.should eq(0)
    session.output.should contain("session-value:persistent-state")
  end
end
