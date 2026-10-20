require "spec"
require "../src/pty"

require "./session/persistent_input_spec"
require "./session/resize_spec"
require "./session/stream_spec"
require "./session/terminate_spec"

describe PTY do
  it "offers direct argv execution through PTY.run" do
    output, exit_code = PTY.run(["/bin/sh", "-c", "printf direct-argv"])

    output.should contain("direct-argv")
    exit_code.should eq(0)
  end

  it "runs a string command with terminal dimensions" do
    output, exit_code = PTY.run("printf direct-string", rows: 30, columns: 100)

    output.should contain("direct-string")
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

  it "accepts an existing Session as the second PTY::Command argument" do
    chunks = [] of String
    session = PTY::Session.new
    command = PTY::Command.new("printf 'command-api'; exit 7", session)
    output, exit_code = command.execute_inside_pty { |chunk| chunks << chunk }

    output.should contain("command-api")
    output.should eq(chunks.join)
    command.session.should be(session)
    exit_code.should eq(7)
  end

  it "keeps the legacy PTY::Command constructor used by tmux.run" do
    command = PTY::Command.new("printf legacy-command", 0, 1_i64)
    output, exit_code = command.execute_inside_pty

    output.should contain("legacy-command")
    exit_code.should eq(0)
  end
end
