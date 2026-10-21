require "spec"
require "../../src/pty"

describe PTY::Session do
  it "preserves one interactive shell across repeated writes" do
    session = PTY::Session.new
    session.start

    session.write("first=persistent\\n")
    session.write("second=state\\n")
    session.write("printf 'session-value:%s-%s\\n' \"$first\" \"$second\"\\n")
    session.wait_for("session-value:persistent-state")

    session.output.should contain("session-value:persistent-state")
  ensure
    session.try(&.terminate)
  end
end
