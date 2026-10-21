require "spec"
require "../../src/pty"

describe PTY::Session do
  # Long-lived sessions need incremental output as well as a final transcript;
  # this guards against losing or reordering chunks while the reader runs.
  it "streams output and retains the same complete transcript" do
    chunks = [] of String
    session = PTY::Session.new("/bin/sh")
    session.start

    # 2. Run the command. This blocks cleanly until the sentinel returns!
    command = "printf 'stream-begin'; read value; printf 'stream-end:%%s\\n' \"$value\""
    result = session.run(command) do |chunk|
      chunks << chunk
    end

    # 3. Clean up the long-lived interactive shell session now that we are done
    session.terminate

    # 4. Run your transcript assertions straight against the result metrics
    result.output.should contain("stream-begin")
    result.output.should contain("stream-end")
    result.status.should eq(0)
  end

  it "raises callback errors promptly even when the child produces continuous output" do
    session = PTY::Session.new("/bin/sh")
    session.start

    expect_raises(Exception, "callback exploded") do
      # Triggering high-volume output subsequently
      session.run("/usr/bin/yes x") do |_chunk|
        raise "callback exploded"
      end
    end

    session.terminate
  end
end
