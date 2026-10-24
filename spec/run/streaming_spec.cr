require "spec"
require "../../src/pty"

describe PTY do
  it "streams data through the one-shot shell API" do
    chunks = [] of String
    output, exit_code = PTY.run("printf 'one-shot-stream'", rows: 30, columns: 100) do |chunk|
      chunks << chunk
    end

    output.should contain("one-shot-stream")
    chunks.join.should contain("one-shot-stream")
    exit_code.should eq(0)
  end
end
