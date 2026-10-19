require "spec"
require "../../src/pty"

describe PTY::Session do
  # Long-lived sessions need incremental output as well as a final transcript;
  # this guards against losing or reordering chunks while the reader runs.
  it "streams output and retains the same complete transcript" do
    chunks = [] of String
    session = PTY::Session.new(["/bin/sh"])
    session.start { |chunk| chunks << chunk }
    session.write("printf 'session-streamed-output\\n'\\n")
    session.write("exit 0\\n")

    session.wait.should eq(0)
    session.output.should contain("session-streamed-output")
    chunks.join.should eq(session.output)
  end
end
