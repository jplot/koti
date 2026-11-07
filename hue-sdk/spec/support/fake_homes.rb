# frozen_string_literal: true

require 'grpc'

# A real gRPC server, without TLS, standing in for the HomeService of the Hue account. ListHomes answers what the
# spec's block returns, and the server keeps the metadata of each call.
class FakeHomes
  # The spec encodes the messages itself; the server marshals an answer through its class.
  Raw = Data.define(:bytes) do
    def self.marshal(raw) = raw.bytes
    def self.unmarshal(bytes) = new(bytes)
  end

  # The one method the gem calls.
  class Service
    include GRPC::GenericService

    self.service_name = 'hue.accounts.v1.HomeService'
    rpc :ListHomes, Raw, Raw

    def initialize(fake)
      @fake = fake
    end

    def list_homes(request, call) = @fake.answer(request, call)
  end

  Call = Data.define(:request, :metadata)

  attr_reader :port, :calls

  def self.start(&answer) = new(answer).tap(&:start)

  def self.message(fields) = fields.map { |tag, value| Array(value).map { field(tag, it) }.join }.join

  def self.field(tag, value)
    case value
    when Integer then varint(tag << 3) + varint(value)
    when true then varint(tag << 3) + varint(1)
    else varint((tag << 3) | 2) + varint(value.bytesize) + value.b
    end
  end

  def self.varint(value)
    bytes = []
    loop do
      byte = value & 0x7f
      value >>= 7
      bytes << (value.zero? ? byte : byte | 0x80)
      return bytes.pack('C*') if value.zero?
    end
  end

  def initialize(answer)
    @answer = answer
    @calls = []
  end

  def start
    @server = GRPC::RpcServer.new(pool_size: 2)
    @port = @server.add_http2_port('127.0.0.1:0', :this_port_is_insecure)
    @server.handle(Service.new(self))
    @thread = Thread.new { @server.run }
    @server.wait_till_running(5)
  end

  def target = "127.0.0.1:#{port}"

  def answer(request, call)
    @calls << Call.new(request: request.bytes, metadata: call.metadata)
    Raw.new(@answer.call)
  end

  def stop
    @server.stop
    @thread.join
  end
end
