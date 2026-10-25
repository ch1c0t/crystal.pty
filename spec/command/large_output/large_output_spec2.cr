require "spec"
require "../../../src/pty"

describe PTY::Command do
  # More data than a PTY buffer can hold exposes reader/writer deadlocks and early
  # process-group cleanup; the return value and streamed chunks must both be complete.
  #
  # It fails with
  #   `crystal spec spec/command/large_output/large_output_spec2.cr`
  #       with
                #        "pty-output\r\n" +
                #        "pty-output\r\n" +
                #        "pty-outyes: standard output: Broken pipe\r\n" +
                #        "END_MARK_1792886696678_105__0__\r\n" +
                #        "$ "
                #
                #      # spec/command/large_output/large_output_spec2.cr:22
                #
                # Finished in 216.6 milliseconds
                # 1 examples, 1 failures, 0 errors, 0 pending
  # but passes with
  #   `crystal spec`
  # Why?
  it "drains output larger than a PTY buffer while the child runs (2)" do
    command = PTY::Command.new("yes pty-output | head -c 131072")
    chunks = [] of String

    output, exit_code = command.execute_inside_pty do |chunk|
      chunks << chunk
    end

    output.bytesize.should be >= 131_072
    chunks.join.should eq(output)
    exit_code.should eq(0)
  end
end
