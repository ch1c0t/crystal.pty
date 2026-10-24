require "spec"
require "../../../src/pty"

describe PTY::Session do
  it "raises callback errors promptly even when the child produces continuous output" do
    session = PTY::Session.new("/bin/sh")
    session.start

    expect_raises(Exception, "callback exploded") do
      session.run("/usr/bin/yes x") do |_chunk|
        raise "callback exploded"
      end
    end

    session.terminate
  end
end
