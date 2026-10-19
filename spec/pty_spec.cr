require "spec"
require "../src/pty"

require "./session/persistent_input_spec"
require "./session/resize_spec"
require "./session/stream_spec"
require "./session/terminate_spec"

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

  it "executes legacy PTY::Command calls through a Session" do
    chunks = [] of String
    command = PTY::Command.new("printf 'command-api'; exit 7", 0, 1_i64)
    output, exit_code = command.execute_inside_pty { |chunk| chunks << chunk }

    output.should contain("command-api")
    output.should eq(chunks.join)
    exit_code.should eq(7)
  end
end
