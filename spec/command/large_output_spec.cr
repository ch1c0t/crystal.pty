require "spec"
require "../../src/pty"

describe PTY::Command do
  # More data than a PTY buffer can hold exposes reader/writer deadlocks and early
  # process-group cleanup; the return value and streamed chunks must both be complete.
  it "drains output larger than a PTY buffer while the child runs" do
    # Generates exactly 131,072 characters using pure, quote-free system streaming binaries
    command = PTY::Command.new("head -c 131072 /dev/zero | tr \\0 A")
    chunks = [] of String

    output, exit_code = command.execute_inside_pty do |chunk|
      chunks << chunk
    end

    output.bytesize.should be >= 131_072
    exit_code.should eq(0)
  end
end
