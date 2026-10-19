require "spec"
require "../../src/pty"

describe PTY::Session do
  # Long-lived sessions need incremental output as well as a final transcript;
  # this guards against losing or reordering chunks while the reader runs.
  it "streams output and retains the same complete transcript" do
    chunks = [] of String
    session = PTY::Session.new(["/bin/sh", "-c", "printf 'stream-begin'; read value; printf 'stream-end:%s\\n' \"$value\""])
    session.start { |chunk| chunks << chunk }
    session.write("payload\n")

    session.wait.should eq(0)
    session.output.should contain("stream-begin")
    session.output.should contain("stream-end:payload")
    chunks.join.should eq(session.output)
  end
end
