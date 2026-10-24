require "spec"
require "../../../src/pty"

describe PTY::Session do
  it "starts the shell in the requested working directory for interactive input" do
    session = PTY::Session.new("/bin/sh", cwd: "/tmp")
    session.start
    session.write("pwd\n")

    session.wait_for("/tmp")
    session.terminate

    session.output.should contain("/tmp")
  end
end
