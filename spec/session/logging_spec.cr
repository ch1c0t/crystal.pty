require "spec"
require "log/spec"
require "../../src/pty"

describe PTY::Session do
  it "emits filterable debug and trace logs under pty.*" do
    session = PTY::Session.new("/bin/sh")

    Log.capture("pty.*", Log::Severity::Trace) do |logs|
      begin
        session.start

        # The startup summary is low-volume and remains visible at DEBUG.
        logs.check(:debug, /Boot Sequence Triggered/)

        # The transcript snapshot and synchronization internals are TRACE-only.
        logs.check(:trace, /Boot Sequence Complete/)
      ensure
        session.terminate
      end
    end
  end
end
