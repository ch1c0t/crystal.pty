require "spec"
require "../../src/pty"

describe PTY::Session do
  it "robustly preserves nested single and double quotation marks inside a single interactive session" do
    # 1. Start a vanilla interactive shell session
    session = PTY::Session.new("/bin/sh")
    session.start

    # 2. Test Case A: Complex nested double quotes inside single quotes (common AWK syntax)
    awk_command = "awk 'BEGIN { print \"double-quotes-inside-single\" }'"
    result_a = session.run(awk_command)

    result_a.status.should eq(0)
    result_a.output.should contain("double-quotes-inside-single")

    # 3. Test Case B: Escaped single quotes inside double quotes (common bash/printf syntax)
    printf_command = "printf \"nested-'single'-quotes\\n\""
    result_b = session.run(printf_command)

    result_b.status.should eq(0)
    result_b.output.should contain("nested-'single'-quotes")

    # 4. Test Case C: Complex combination of quotes, pipes, and variables running sequentially
    # This verifies that the evaluation does not leak or break the long-lived session context
    compound_command = "echo \"step-1\" | awk '{ print $1 \"-and-step-2\" }'"
    result_c = session.run(compound_command)

    result_c.status.should eq(0)
    result_c.output.should contain("step-1-and-step-2")

    # 5. Clean up the session resources cleanly
    session.terminate
  end
end
