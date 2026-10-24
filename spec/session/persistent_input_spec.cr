require "spec"
require "../../src/pty"

describe PTY::Session do
  it "preserves one process across repeated writes" do
    session = PTY::Session.new("/bin/sh")
    session.start

    # Write the persistent sequence command directly to the active shell context
    session.write("/bin/sh -c 'read first; read second; printf \"session-value:%s-%s\\n\" \"$first\" \"$second\"'\n")
    sleep(20.milliseconds)

    session.write("persistent\n")
    sleep(20.milliseconds)
    session.write("state\n")

    # Let data settle cleanly in the master transcript
    session.wait_for("session-value:persistent-state")
    p "before session.terminate"
    session.terminate

    p "before session.output"
    session.output.should contain("session-value:persistent-state")
  end
end
