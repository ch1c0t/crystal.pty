require "spec"
require "../../src/pty"

describe PTY::Session do
  it "starts an interactive shell when no command is provided" do
    session = PTY::Session.new(rows: 42, columns: 120)
    session.start
    session.write("stty size\nprintf 'interactive-session-ok\\n'\nexit\n")

    exit_code = session.wait

    session.output.should contain("42 120")
    session.output.should contain("interactive-session-ok")
    exit_code.should eq(0)
  end

  it "accepts a shell name and configures the terminal environment" do
    session = PTY::Session.new("sh", name: "xterm-color", env: {"PTY_SESSION_TEST" => "configured"})
    session.start
    session.write("printf '%s %s\\n' \"$TERM\" \"$PTY_SESSION_TEST\"\nexit\n")

    exit_code = session.wait

    session.output.should contain("xterm-color configured")
    exit_code.should eq(0)
  end

  it "starts the shell in the requested working directory" do
    session = PTY::Session.new("/bin/sh", cwd: "/tmp")
    session.start
    session.write("pwd\nexit\n")

    exit_code = session.wait

    session.output.should contain("/tmp")
    exit_code.should eq(0)
  end
end
