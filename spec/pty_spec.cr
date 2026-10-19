require "spec"
require "../src/pty"

describe PTY do
  it "offers the one-shot argv API" do
    output, exit_code = PTY.run(["/bin/sh", "-c", "printf direct-argv"])

    output.should contain("direct-argv")
    exit_code.should eq(0)
  end

  it "streams data through the one-shot shell API" do
    chunks = [] of String
    output, exit_code = PTY.run("printf 'one-shot-stream'", rows: 30, columns: 100) do |chunk|
      chunks << chunk
    end

    output.should eq(chunks.join)
    exit_code.should eq(0)
  end
end
