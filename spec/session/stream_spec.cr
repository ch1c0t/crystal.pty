require "spec"
require "../../src/pty"

describe PTY::Session do
  # Long-lived sessions need incremental output as well as a final transcript;
  # this guards against losing or reordering chunks while the reader runs.
  it "raises callback errors promptly even when the child produces continuous output" do
    session = PTY::Session.new
    started_at = Time.instant

    expect_raises(Exception, "callback exploded") do
      session.start(["/usr/bin/timeout", "--foreground", "--signal=KILL", "2",
                     "/usr/bin/yes", "x"]) do |_chunk|
        raise "callback exploded"
      end
      session.wait
    end

    (Time.instant - started_at).should be < 1.second
  end

  it "drains the final output before closing the PTY master" do
    chunks = [] of String
    session = PTY::Session.new
    payload_size = 1_048_576
    marker = "FINAL-OUTPUT-MARKER"

    command = "head -c #{payload_size} /dev/zero | tr '\\000' x; printf '\\n#{marker}\\n'"
    session.start(["/bin/sh", "-c", command]) { |chunk| chunks << chunk }

    exit_code = session.wait

    session.output.count("x").should eq(payload_size)
    session.output.should contain(marker)
    chunks.join.should eq(session.output)
    exit_code.should eq(0)
  end

  it "streams output and retains the same complete transcript" do
    chunks = [] of String
    session = PTY::Session.new

    args = ["/usr/bin/timeout", "--foreground", "5", "/bin/sh", "-c", "printf 'stream-begin'; read value; printf 'stream-end:%s\\n' \"$value\""]
    session.start(args) { |chunk| chunks << chunk }
    session.write("payload\n")

    exit_code = session.wait
    session.output.should contain("stream-begin")
    session.output.should contain("stream-end:payload")
    chunks.join.should eq(session.output)
    exit_code.should eq(0)
  end
end
