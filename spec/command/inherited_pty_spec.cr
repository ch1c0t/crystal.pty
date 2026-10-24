require "spec"
require "../../src/pty"

describe PTY::Command do
  # A background descendant can keep the PTY slave open after the leader exits;
  # this guards against waiting indefinitely for EOF from a process that has exited.
  it "does not wait forever for descendants which inherit the PTY" do
    command = PTY::Command.new("sleep 10 </dev/tty >/dev/tty 2>&1 & printf leader-exited; exit 0")
    started_at = Time.instant

    output, exit_code = command.execute_inside_pty { |_chunk| }

    (Time.instant - started_at).should be < 3.seconds
    output.should contain("leader-exited")
    exit_code.should eq(0)
  end
end
