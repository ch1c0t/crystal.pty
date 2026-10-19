require "spec"
require "../../src/pty"

describe "PTY::Command dimensions" do
  it "preserves the native PTY size when no dimensions are supplied" do
    command = PTY::Command.new("if [ -t 0 ]; then printf terminal; fi")

    output, exit_code = command.execute_inside_pty { |_chunk| }

    output.should contain("terminal")
    exit_code.should eq(0)
  end

  it "supports caller-specified terminal dimensions" do
    command = PTY::Command.new("stty size", rows: 42, columns: 120)

    output, exit_code = command.execute_inside_pty { |_chunk| }

    output.should contain("42 120")
    exit_code.should eq(0)
  end

  it "validates argv and terminal dimensions" do
    expect_raises(ArgumentError, "PTY command must not be empty") do
      PTY::Command.new([] of String)
    end
    expect_raises(ArgumentError, "PTY rows and columns must be provided together") do
      PTY::Command.new("true", rows: 30)
    end
    expect_raises(ArgumentError, "PTY rows must be between 1 and 65535") do
      PTY::Command.new("true", rows: 0, columns: 80)
    end
  end
end
