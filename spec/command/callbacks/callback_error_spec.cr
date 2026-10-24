require "spec"
require "../../../src/pty"

describe PTY::Command do
  # A failing consumer must not strand the child or PTY reader; callers need
  # their original callback exception after process resources have been cleaned up.
  it "propagates stream callback errors after cleaning up the child" do
    command = PTY::Command.new("printf 'callback-error-test'; sleep 1")

    expect_raises(ArgumentError, "stream sink failed") do
      command.execute_inside_pty do |_chunk|
        raise ArgumentError.new("stream sink failed")
      end
    end
  end
end
