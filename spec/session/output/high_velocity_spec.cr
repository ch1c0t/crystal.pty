require "spec"
require "../../../src/pty"

describe PTY::Session do
  it "handles high-velocity real-time text streams over multiple ticks" do
    ticks = [] of String
    session = PTY::Session.new("/bin/sh")
    session.start

    command = "for i in $(seq 1 5); do echo \"Tick $i\" && sleep 0.01; done"
    result = session.run(command) do |chunk|
      ticks << chunk
    end

    session.terminate

    result.output.should contain("Tick 1")
    result.output.should contain("Tick 5")
    ticks.join.should contain("Tick 3")
  end
end
