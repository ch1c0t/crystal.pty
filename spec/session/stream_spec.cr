require "spec"
require "../../src/pty"

describe PTY::Session do
  it "streams command output and returns the same command transcript" do
    chunks = [] of String
    session = PTY::Session.new
    session.start

    output, exit_code = session.run("printf 'stream-begin'; printf 'stream-end\\n'") do |chunk|
      chunks << chunk
    end

    output.should contain("stream-begin")
    output.should contain("stream-end")
    chunks.join.should eq(output)
    exit_code.should eq(0)
  ensure
    session.terminate
  end

  it "raises callback errors promptly when a command produces continuous output" do
    session = PTY::Session.new
    session.start
    started_at = Time.instant

    expect_raises(Exception, "callback exploded") do
      session.run("timeout --foreground --signal=KILL 2 /usr/bin/yes x") do |_chunk|
        raise "callback exploded"
      end
    end

    (Time.instant - started_at).should be < 1.second
  ensure
    session.terminate
  end
end
