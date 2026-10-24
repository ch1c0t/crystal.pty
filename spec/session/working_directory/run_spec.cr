require "spec"
require "../../../src/pty"

describe PTY::Session do
  it "runs a command in the requested working directory" do
    session = PTY::Session.new("/bin/sh", cwd: "/tmp")
    session.start

    result = session.run("pwd")
    result.status.should eq(0)
    session.output.should contain("/tmp")

    session.terminate
  end
end
