require "spec"
require "../../../src/pty"

describe PTY::Command do
  it "accepts an existing Session as the second constructor argument" do
    chunks = [] of String
    session = PTY::Session.new("/bin/sh")
    session.start

    command = PTY::Command.new("printf 'command-api'; exit 7", session)
    output, exit_code = command.execute_inside_pty { |chunk| chunks << chunk }

    output.should contain("command-api")
    chunks.join.should contain("command-api")
    command.session.should be(session)
    exit_code.should eq(7)

    # "exit" must terminate only the command subshell, not the persistent session.
    follow_up = session.run("printf 'session-still-alive'")
    follow_up.output.should eq("session-still-alive")
    follow_up.status.should eq(0)
  end
end
