require "spec"
require "../../src/pty"

describe PTY::Session do
  # Multiple input writes must reach one surviving process; the child reads
  # two lines and combines them, proving this is not a new PTY per write.
  it "preserves one process across repeated writes" do
    session = PTY::Session.new
    session.start(["/usr/bin/timeout", "--foreground", "5", "/bin/sh", "-c", "read first; read second; printf 'session-value:%s-%s\\n' \"$first\" \"$second\""])

    session.write("persistent\n")
    session.write("state\n")

    exit_code = session.wait
    session.output.should contain("session-value:persistent-state")
    exit_code.should eq(0)
  end
end
