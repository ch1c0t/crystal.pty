require "spec"
require "../../../src/pty"

describe PTY::Session do
  it "starts an interactive shell with the requested terminal dimensions" do
    session = PTY::Session.new(rows: 42, columns: 120)
    session.start

    session.write("stty size\n")
    session.wait_for("42 120")

    session.write("printf 'interactive-session-ok\\n'\n")
    session.wait_for("interactive-session-ok")

    session.output.should contain("42 120")
    session.output.should contain("interactive-session-ok")

    session.terminate
  end
end
