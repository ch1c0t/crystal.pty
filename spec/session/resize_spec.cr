require "spec"
require "../../src/pty"

describe PTY::Session do
  # Resizing must update the actual terminal kernel state, not only Session's
  # metadata; terminal programs discover the new dimensions through TIOCSWINSZ.
  it "changes the dimensions of the existing PTY" do
    session = PTY::Session.new(["/usr/bin/timeout", "5", "/bin/sh", "-c", "read proceed; stty size"], rows: 24, columns: 80)
    session.start
    session.resize(rows: 42, columns: 120)
    session.write("proceed\n")

    session.wait.should eq(0)
    session.output.should contain("42 120")
  end
end
