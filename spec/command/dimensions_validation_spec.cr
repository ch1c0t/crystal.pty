require "spec"
require "../../src/pty"

describe PTY::Command do
  # Reject invalid configuration before fork/ioctl: an empty argv or incomplete
  # or out-of-range terminal size should fail clearly instead of launching badly.
  it "validates argv and terminal dimensions" do
    expect_raises(ArgumentError, "PTY command must not be empty") do
      PTY::Command.new([] of String)
    end
    expect_raises(ArgumentError, "PTY rows and columns must be provided together") do
      session = PTY::Session.new rows: 30
      PTY::Command.new("true", session)
    end
    expect_raises(ArgumentError, "PTY rows must be between 1 and 65535") do
      session = PTY::Session.new rows: 0, columns: 80
      PTY::Command.new("true", session)
    end
  end
end
