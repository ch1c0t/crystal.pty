require "spec"
require "../../src/pty"

describe PTY::Session do
  it "starts an interactive shell with the requested terminal dimensions" do
    session = PTY::Session.new(rows: 42, columns: 120)
    session.start

    # Step A: Write the first command and wait explicitly for its output pattern
    session.write("stty size\n")
    session.wait_for("42 120") # <--- First Sentinel sync guard

    # Step B: Write the final completion token
    session.write("printf 'interactive-session-ok\\n'\n")
    session.wait_for("interactive-session-ok") # <--- Second Sentinel sync guard

    # Now both blocks are guaranteed to be fully flushed in order inside session.output
    session.output.should contain("42 120")
    session.output.should contain("interactive-session-ok")

    session.terminate
  end

  it "accepts a shell name and configures the terminal environment" do
    session = PTY::Session.new("sh", name: "xterm-color", env: {"PTY_SESSION_TEST" => "configured"})
    session.start
    session.write("printf '%s %s\\n' \"$TERM\" \"$PTY_SESSION_TEST\"\n")

    # Block exactly long enough for the target text to flush into the buffer
    session.wait_for("xterm-color configured")
    session.terminate

    session.output.should contain("xterm-color configured")
  end

  it "starts the shell in the requested working directory" do
    session = PTY::Session.new("/bin/sh", cwd: "/tmp")
    session.start
    session.write("pwd\n")

    # Block explicitly until /tmp manifests in the PTY stream
    session.wait_for("/tmp")
    session.terminate

    session.output.should contain("/tmp")
  end

  it "starts the shell in the requested working directory 2" do
    session = PTY::Session.new("/bin/sh", cwd: "/tmp")
    session.start

    result = session.run("pwd")
    result.status.should eq(0)
    session.output.should contain("/tmp")

    session.terminate
  end
end
