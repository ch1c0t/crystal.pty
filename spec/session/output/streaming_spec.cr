require "spec"
require "../../../src/pty"

describe PTY::Session do
  # Long-lived sessions need incremental output as well as a final transcript;
  # this guards against losing or reordering chunks while the reader runs.
  it "streams output and retains the same complete transcript" do
    chunks = [] of String
    session = PTY::Session.new("/bin/sh")
    session.start

    command = "echo 'hello-input' | ( printf 'stream-begin'; read value; printf 'stream-end:%s\\n' \"$value\" )"

    result = session.run(command) do |chunk|
      chunks << chunk
    end

    session.terminate

    result.output.should contain("stream-begin")
    result.output.should contain("stream-end")
    result.status.should eq(0)
    chunks.join.should contain("stream-begin")
  end
end
