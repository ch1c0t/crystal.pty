require "spec"
require "../../src/pty"

describe PTY::Session do
  it "starts a shell with the requested terminal dimensions" do
    session = PTY::Session.new(rows: 42, columns: 120)
    session.start

    output, status = session.run("stty size")
    output.should contain("42 120")
    status.should eq(0)

    output, status = session.run("printf 'interactive-session-ok\\n'")
    output.should contain("interactive-session-ok")
    status.should eq(0)
  ensure
    session.terminate
  end

  it "accepts a shell name and configures the terminal environment" do
    session = PTY::Session.new("sh", name: "xterm-color", env: {"PTY_SESSION_TEST" => "configured"})
    session.start

    output, status = session.run("printf '%s %s\\n' \"$TERM\" \"$PTY_SESSION_TEST\"")
    output.should contain("xterm-color configured")
    status.should eq(0)
  ensure
    session.terminate
  end

  it "starts the shell in the requested working directory" do
    session = PTY::Session.new("/bin/sh", cwd: "/tmp")
    session.start

    output, status = session.run("pwd")
    output.should contain("/tmp")
    status.should eq(0)
  ensure
    session.terminate
  end
end
