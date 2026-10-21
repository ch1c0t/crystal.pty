require "spec"
require "../../src/pty"

describe PTY::Session do
  it "changes the dimensions of the existing PTY" do
    # Pass a valid shell binary to the constructor
    session = PTY::Session.new("/bin/sh", rows: 24, columns: 80)
    session.start

    # Dynamically change layout properties live over the TTY wire
    session.resize(rows: 42, columns: 120)

    # Execute the testing command block inside the shell context
    session.run("/usr/bin/timeout 5 /bin/sh -c 'read proceed; stty size'")

    # Signal the reading blocker to complete
    session.write("proceed\n")

    session.output.should contain("42 120")
    session.terminate
  end
end
