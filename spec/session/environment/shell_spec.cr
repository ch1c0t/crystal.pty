require "spec"
require "../../../src/pty"

describe PTY::Session do
  it "accepts a shell name and configures the terminal environment" do
    session = PTY::Session.new("sh", name: "xterm-color", env: {"PTY_SESSION_TEST" => "configured"})
    session.start
    session.write("printf '%s %s\\n' \"$TERM\" \"$PTY_SESSION_TEST\"\n")

    session.wait_for("xterm-color configured")
    session.terminate

    session.output.should contain("xterm-color configured")
  end
end
