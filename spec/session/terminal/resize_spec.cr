require "spec"
require "../../../src/pty"

describe PTY::Session do
  it "changes the dimensions of the existing PTY" do
    # Pass a valid shell binary to the constructor
    session = PTY::Session.new("/bin/sh", rows: 24, columns: 80)
    session.start

    # Dynamically change layout properties live over the TTY wire
    session.resize(rows: 42, columns: 120)

    # FIX: Send the command using non-blocking write instead of synchronous run
    session.write("/usr/bin/timeout 5 /bin/sh -c 'read proceed; stty size'\n")

    # Give the PTY a tiny scheduling moment to register the read state, then feed the trigger
    Fiber.yield
    session.write("proceed\n")

    # Use the streaming wait_for shield to catch the expected target output layout
    session.wait_for("42 120")

    # Validate the log state holds the values accurately
    session.output.should contain("42 120")
    session.terminate
  end
end
