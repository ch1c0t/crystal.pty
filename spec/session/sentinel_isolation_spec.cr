require "spec"
require "../../src/pty"

describe PTY::Session do
  it "isolates the command output perfectly and leaves no sentinel noise in result.output" do
    # 1. Boot up a vanilla interactive shell session
    session = PTY::Session.new("/bin/sh")
    session.start
    session.wait_for("$ ") rescue nil

    # 2. Run a clean text echo command
    result = session.run("echo 'verify-clean-transcript'")

    # 3. VERIFICATION A: The output must contain the exact expected command result
    result.output.should eq("verify-clean-transcript")

    # 4. VERIFICATION B: The transcript must be completely free of infrastructure tracking markers
    result.output.should_not contain("START_MARK")
    result.output.should_not contain("END_MARK")
    result.output.should_not contain("__$?__")

    # 5. VERIFICATION C: Ensure the global historical log *does* contain them,
    # proving the backend is using them but successfully filtering them for the user!
    session.output.should contain("START_MARK")
    session.output.should contain("END_MARK")

    session.terminate
  end
end
