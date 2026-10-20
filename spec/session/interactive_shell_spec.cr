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
end
