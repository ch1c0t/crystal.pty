require "spec"
require "../../../src/pty"

describe PTY::Session do
  # A single spec launches multiple children in one Crystal process. This detects
  # regressions caused by invoking Crystal's allocating Process.exec path after fork.
  it "repeatedly launches a shell without a child-side runtime crash" do
    20.times do |index|
      session = PTY::Session.new("/bin/sh")

      begin
        session.start

        # Print READY using octal escapes so it isn't present in the echoed command.
        token = "READY-#{Process.pid}-#{index}"
        result = session.run("printf '\\122\\105\\101\\104\\131-#{Process.pid}-#{index}\\n'")

        result.output.should contain(token)
        result.status.should eq(0)
        session.alive?.should be_true
      ensure
        session.terminate
      end
    end
  end
end
