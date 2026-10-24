require "spec"
require "../../src/pty"

describe PTY::Session do
  # Explicit termination must close a running process group and unblock the
  # PTY reader, rather than leaving fibers or descriptors behind.
  it "terminates a running process and waits for cleanup" do
    # Configure the long-running sleep command onto the shell option during initialization
    session = PTY::Session.new(shell: "/bin/sh -c 'sleep 30'")
    
    # Call the clean, zero-argument start method
    session.start

    started_at = Time.instant
    session.terminate

    (Time.instant - started_at).should be < 3.seconds
    session.alive?.should be_false
  end
end
